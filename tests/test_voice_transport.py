import asyncio
from contextlib import asynccontextmanager
import json
import unittest
from voice_relay.transport import SpeechTransport, TransportError


class Ledger:
    def __init__(self):
        self.reserved = []; self.settled = []
    def reserve(self, value):
        self.reserved.append(value); return 'ticket'
    def settle(self, ticket, value):
        self.settled.append((ticket, value))


class Socket:
    def __init__(self, *, bad_ack=False, silent=False, fail=False):
        self.messages = asyncio.Queue()
        self.messages.put_nowait(json.dumps({'type': 'error'} if bad_ack else {'sessionId': 'test'}))
        self.sent = []; self.closed = False; self.silent = silent; self.fail = fail
    async def send(self, value):
        self.sent.append(value)
        if isinstance(value, bytes) and self.fail:
            await self.messages.put(json.dumps({'type': 'error', 'message': 'secret-example'}))
        if value == '{"type":"endStream"}' and not self.silent:
            for event in [dict(type='speechStart', turnId=1, audioProcessedMs=10),
                          dict(type='speechComplete', turnId=1, audioProcessedMs=10, transcript='Hola'),
                          dict(type='transcript', audioProcessedMs=20, transcript='Hola', final=True), None]:
                await self.messages.put(None if event is None else json.dumps(event))
    async def recv(self):
        return await self.messages.get()
    @asynccontextmanager
    async def connect(self):
        try:
            yield self
        finally:
            self.closed = True


async def frames():
    yield b'\0' * 480


class TransportTests(unittest.IsolatedAsyncioTestCase):
    def make(self, **options):
        self.socket = Socket(**options); self.ledger = Ledger(); self.updates = []
        self.transport = SpeechTransport(self.ledger, connect=self.socket.connect,
                                         key=lambda: 'secret-example', max_seconds=.1,
                                         drain_seconds=.03, io_timeout=.05)
    async def update(self, value):
        self.updates.append(value)
    async def run_stream(self, source_frames=None, consent=True):
        return await self.transport.run(source_frames or frames(), self.update, source='fixture', consent=consent)
    async def test_selected_language_bias_reaches_provider_handshake(self):
        self.make()
        await self.transport.run(frames(), self.update, source='fixture', consent=True,
                                 language_bias=['French', 'Japanese'])
        self.assertEqual(json.loads(self.socket.sent[0])['languageBias'], ['French', 'Japanese'])

    async def test_complete_handshake_final_and_accounting(self):
        self.make()
        receipt = await self.run_stream()
        handshake = json.loads(self.socket.sent[0])
        self.assertEqual(handshake['mode'], 'ENDPOINTING')
        self.assertEqual(handshake['partialMode'], 'CUMULATIVE')
        self.assertEqual(handshake['languageBias'], ['English', 'Spanish'])
        self.assertEqual(receipt.bytes_sent, 480)
        self.assertEqual(receipt.completed_turns, 1)
        self.assertEqual(self.updates[-1].text, 'Hola')
        self.assertTrue(self.socket.closed)
        self.assertFalse(self.transport.core.active)
        self.assertEqual(self.ledger.settled, [('ticket', 50000)])
    async def test_no_consent_no_charge_no_send(self):
        self.make()
        with self.assertRaises(TransportError):
            await self.run_stream(consent=False)
        self.assertEqual(self.ledger.reserved, [])
        self.assertEqual(self.socket.sent, [])
    async def test_bad_handshake_never_sends_audio(self):
        self.make(bad_ack=True)
        with self.assertRaises(TransportError):
            await self.run_stream()
        self.assertEqual(len(self.socket.sent), 1)
        self.assertEqual(self.ledger.settled, [])
        self.assertTrue(self.socket.closed)
    async def test_silent_drain_closes_with_reservation(self):
        self.make(silent=True)
        with self.assertRaises(TransportError):
            await asyncio.wait_for(self.run_stream(), .5)
        self.assertTrue(self.socket.closed)
        self.assertEqual(self.ledger.settled, [])
    async def test_bad_pcm_is_not_sent(self):
        self.make()
        async def invalid():
            yield b'odd'
        with self.assertRaises(TransportError):
            await self.run_stream(invalid())
        self.assertFalse(any(isinstance(x, bytes) for x in self.socket.sent))
        self.assertTrue(self.socket.closed)
    async def test_cancellation_stops_capture_and_clears_state(self):
        self.make(silent=True)
        closed = asyncio.Event()
        async def stalled():
            try:
                yield b'\0\0'
                await asyncio.Event().wait()
            finally:
                closed.set()
        task = asyncio.create_task(self.run_stream(stalled()))
        while not any(isinstance(x, bytes) for x in self.socket.sent):
            await asyncio.sleep(.001)
        task.cancel()
        with self.assertRaises(asyncio.CancelledError):
            await task
        self.assertTrue(closed.is_set())
        self.assertTrue(self.socket.closed)
        self.assertFalse(self.transport.running)
        self.assertEqual(self.transport.core.turns, {})
    async def test_provider_error_sanitized_and_sender_cancelled(self):
        self.make(fail=True)
        async def stalled():
            yield b'\0\0'
            await asyncio.Event().wait()
        with self.assertRaises(TransportError) as error:
            await self.run_stream(stalled())
        self.assertNotIn('secret-example', str(error.exception))
        self.assertTrue(self.socket.closed)
        self.assertEqual(self.ledger.settled, [])
    async def test_stalled_source_wall_limit(self):
        self.make()
        async def stalled():
            await asyncio.Event().wait()
            yield b'\0\0'
        with self.assertRaises(TransportError):
            await asyncio.wait_for(self.run_stream(stalled()), .5)
        self.assertTrue(self.socket.closed)


if __name__ == '__main__':
    unittest.main()
