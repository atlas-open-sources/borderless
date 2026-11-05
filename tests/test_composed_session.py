"""Real loopback + production pipeline/ASR parser, synthetic provider boundaries."""
import asyncio
from contextlib import asynccontextmanager
import json
import unittest

from websockets.asyncio.client import connect
from websockets.asyncio.server import serve
from conversation_relay.server import SessionServer, MAX_HANDSHAKE
from conversation_relay.pipeline import SpeechConversation
from voice_relay.transport import SpeechTransport


class MemoryLedger:
    def __init__(self):
        self.reserved = []
        self.settled = []

    def reserve(self, value):
        self.reserved.append(value)
        return len(self.reserved)

    def settle(self, ticket, value):
        self.settled.append((ticket, value))


class ProviderSocket:
    def __init__(self, transcript):
        self.transcript = transcript
        self.messages = asyncio.Queue()
        self.messages.put_nowait(json.dumps({'sessionId': 'synthetic'}))
        self.audio = []
        self.closed = False

    async def send(self, value):
        if isinstance(value, bytes):
            self.audio.append(value)
        elif value == '{"type":"endStream"}':
            for event in [dict(type='speechStart', turnId=1, audioProcessedMs=10),
                          dict(type='transcript', audioProcessedMs=10,
                               transcript=self.transcript[:4], final=False),
                          dict(type='speechComplete', turnId=1, audioProcessedMs=10,
                               transcript=self.transcript),
                          dict(type='transcript', audioProcessedMs=20,
                               transcript=self.transcript, final=True)]:
                self.messages.put_nowait(json.dumps(event))
            self.messages.put_nowait(None)

    async def recv(self):
        return await self.messages.get()

    @asynccontextmanager
    async def connect(self):
        try:
            yield self
        finally:
            self.closed = True


class TextProvider:
    def __init__(self):
        self.prompts = []
        self.fail = False
        self.started = asyncio.Event()
        self.hold = None
        self.cancelled = False

    async def generate(self, prompt, limit):
        data = json.loads(prompt.split('Conversation data:\n')[1])
        self.prompts.append(data)
        self.started.set()
        if self.hold is not None:
            try:
                await self.hold.wait()
            except asyncio.CancelledError:
                self.cancelled = True
                raise
        if self.fail:
            raise RuntimeError('synthetic-provider-private-error')
        guest = data['suggest_replies_for_english_host']
        replies = [dict(text='Bien', gloss='Well', pronunciation='byen'),
                   dict(text='No muy bien', gloss='Not very well', pronunciation='no mwee byen')] if guest else []
        value = dict(translation='How are you?' if guest else 'Estoy bien.', replies=replies)
        return {'output': [{'content': [{'type': 'output_text', 'text': json.dumps(value)}]}]}


class ComposedSessionTests(unittest.IsolatedAsyncioTestCase):
    async def test_ready_waits_for_provider_handshake(self):
        gate = asyncio.Event()
        entered = asyncio.Event()
        class DelayedProvider(ProviderSocket):
            async def recv(self):
                if not entered.is_set():
                    entered.set()
                    await gate.wait()
                return await super().recv()
        provider = DelayedProvider('¿Cómo estás?')
        speech = SpeechTransport(MemoryLedger(), connect=provider.connect, key=lambda: 'synthetic',
                                 max_seconds=2, drain_seconds=.3, io_timeout=1)
        service = SessionServer('synthetic-readiness-token-' * 2,
                                lambda: SpeechConversation(speech, TextProvider()))
        async with serve(service.handle, '127.0.0.1', 0, origins=[None], max_size=MAX_HANDSHAKE) as listener:
            port = listener.sockets[0].getsockname()[1]
            async with connect(f'ws://127.0.0.1:{port}', proxy=None) as client:
                await client.send(json.dumps(dict(type='start', token=service.token,
                                                  participant='guest', consent=True)))
                ready = asyncio.create_task(client.recv())
                await asyncio.wait_for(entered.wait(), 1)
                try:
                    await asyncio.sleep(.1)
                    self.assertFalse(ready.done(), 'Phone must not start audio before provider acknowledges')
                finally:
                    gate.set()
                    event = await ready
                self.assertEqual(json.loads(event), {'type': 'started'})
                await client.send(bytes(480))
                await client.send('{"type":"end"}')
                events = [json.loads(value) async for value in client]
                self.assertEqual([e['type'] for e in events][-2:], ['completed', 'stopped'])

    async def test_pcm_to_two_recipient_translation_and_context(self):
        await self.exercise(fail=False)

    async def test_translation_failure_closes_composed_session(self):
        await self.exercise(fail=True)

    async def test_stop_during_translation_cancels_without_delivering_reply(self):
        token = 'synthetic-loopback-token-' * 2
        text = TextProvider()
        text.hold = asyncio.Event()
        provider = ProviderSocket('¿Cómo estás?')
        speech = SpeechTransport(MemoryLedger(), connect=provider.connect, key=lambda: 'synthetic-only',
                                 max_seconds=1, drain_seconds=.2, io_timeout=.2)
        pipeline = SpeechConversation(speech, text)
        service = SessionServer(token, lambda: pipeline)
        async with serve(service.handle, '127.0.0.1', 0, origins=[None]) as listener:
            port = listener.sockets[0].getsockname()[1]
            async with asyncio.timeout(3):
                async with connect(f'ws://127.0.0.1:{port}', proxy=None) as client:
                    await client.send(json.dumps(dict(type='start', token=token,
                                                      participant='guest', consent=True)))
                    self.assertEqual(json.loads(await client.recv()), {'type': 'started'})
                    await client.send(bytes(480))
                    await client.send('{"type":"end"}')
                    await text.started.wait()
                    await client.send('{"type":"stop"}')
                    events = [json.loads(value) async for value in client]
            self.assertEqual(events[-1], {'type': 'stopped'})
            self.assertTrue(any(e['type'] == 'partial' for e in events))
            self.assertFalse(any(e['type'] == 'turn' for e in events))
            self.assertTrue(all(not e['turn']['replies'] for e in events if e['type'] == 'partial'))
            self.assertTrue(text.cancelled)
            self.assertTrue(provider.closed)
            self.assertFalse(pipeline.running)
            self.assertFalse(speech.running)
            self.assertEqual(service.active, 0)

    async def exercise(self, fail):
        token = 'synthetic-loopback-token-' * 2
        text = TextProvider()
        text.fail = fail
        records = []
        transcripts = iter(['¿Cómo estás?', 'I am well.'])

        def factory():
            provider = ProviderSocket(next(transcripts))
            ledger = MemoryLedger()
            speech = SpeechTransport(ledger, connect=provider.connect, key=lambda: 'synthetic-only',
                                     max_seconds=1, drain_seconds=.2, io_timeout=.2)
            pipeline = SpeechConversation(speech, text)
            records.append((provider, ledger, speech, pipeline))
            return pipeline

        service = SessionServer(token, factory)
        context = []
        async with serve(service.handle, '127.0.0.1', 0, origins=[None], max_size=MAX_HANDSHAKE) as listener:
            port = listener.sockets[0].getsockname()[1]
            for speaker in (['guest'] if fail else ['guest', 'host']):
                async with asyncio.timeout(3):
                    async with connect(f'ws://127.0.0.1:{port}', proxy=None) as client:
                        await client.send(json.dumps(dict(type='start', token=token, participant=speaker,
                                                          consent=True, context=context)))
                        self.assertEqual(json.loads(await client.recv()), {'type': 'started'})
                        pcm = bytes(480)
                        await client.send(pcm)
                        await client.send('{"type":"end"}')
                        events = [json.loads(value) async for value in client]
                partials = [event for event in events if event['type'] == 'partial']
                self.assertEqual([e['audience'] for e in partials], ['host', 'guest', 'host', 'guest'])
                self.assertTrue(all(e['turn']['status'] == 'pending' and e['turn']['translation'] == ''
                                    and e['turn']['replies'] == [] for e in partials))
                self.assertEqual(partials[-1]['turn']['source'], records[-1][0].transcript)
                terminal = [event for event in events if event['type'] != 'partial']
                if fail:
                    self.assertEqual([event['type'] for event in terminal], ['stopped', 'error'])
                    self.assertNotIn('synthetic-provider-private-error', json.dumps(events))
                else:
                    self.assertEqual([event['type'] for event in terminal], ['turn', 'turn', 'completed', 'stopped'])
                    host, guest = terminal[:2]
                    self.assertEqual(host['turn']['revision'], partials[-1]['turn']['revision'])
                    self.assertLess(events.index(partials[-1]), events.index(host))
                    self.assertEqual((host['audience'], guest['audience']), ('host', 'guest'))
                    self.assertEqual(host['turn']['source'], records[-1][0].transcript)
                    self.assertEqual(host['turn']['translation'], guest['turn']['translation'])
                    self.assertEqual(len(host['turn']['replies']), 2 if speaker == 'guest' else 0)
                    self.assertEqual(guest['turn']['replies'], [])
                    self.assertEqual(text.prompts[-1]['context'], context)
                    context.append(dict(speaker=speaker, source=host['turn']['source']))
                provider, ledger, speech, pipeline = records[-1]
                self.assertEqual(provider.audio, [pcm])
                self.assertTrue(provider.closed)
                self.assertFalse(speech.running)
                self.assertFalse(pipeline.running)
                self.assertFalse(pipeline.conversation.active)
                self.assertEqual(len(ledger.reserved), 1)
                self.assertEqual(len(ledger.settled), 1)
                self.assertEqual(service.active, 0)
        self.assertEqual(len(text.prompts), 1 if fail else 2)
