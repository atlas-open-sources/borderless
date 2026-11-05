import asyncio
import json
import unittest
from conversation_relay.server import SessionServer, MAX_HANDSHAKE

TOKEN = 'synthetic-token-' * 3


class Socket:
    def __init__(self, start):
        self.incoming = asyncio.Queue()
        self.incoming.put_nowait(json.dumps(start, ensure_ascii=False))
        self.sent = []
        self.closed = False
    async def recv(self):
        return await self.incoming.get()
    async def send(self, value):
        self.sent.append(json.loads(value))
    async def close(self):
        self.closed = True


class Pipeline:
    def __init__(self):
        self.started = asyncio.Event()
        self.cancelled = False
        self.audio = []
        self.speaker = None
        self.context = None
    async def run(self, frames, emit, **kwargs):
        self.speaker = kwargs['participant'](None)
        self.context = kwargs['context']
        self.started.set()
        try:
            async for frame in frames:
                self.audio.append(frame)
            await emit({'type': 'completed'})
        except asyncio.CancelledError:
            self.cancelled = True
            raise


class ServerTests(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        self.pipeline = Pipeline()
        self.calls = 0
        def factory():
            self.calls += 1
            return self.pipeline
        self.server = SessionServer(TOKEN, factory)
        self.start = dict(type='start', token=TOKEN, participant='guest', consent=True)
    async def test_unauthorized_cannot_start_paid_work(self):
        for changes in ({'token': 'wrong'}, {'consent': False}, {'participant': 'unknown'}):
            socket = Socket(dict(self.start, **changes))
            await self.server.handle(socket)
            self.assertTrue(socket.closed)
            self.assertEqual(socket.sent[-1]['type'], 'error')
        self.assertEqual(self.calls, 0)
    async def test_invalid_context_rejected_before_pipeline_factory(self):
        invalid = [None, {}, 'text', [None],
                   [{'speaker': 'host', 'source': 'x'}] * 7,
                   [{'speaker': 'other', 'source': 'x'}],
                   [{'speaker': 'host', 'source': ' '}],
                   [{'speaker': 'host', 'source': 3}],
                   [{'speaker': 'host', 'source': 'x' * 2001}],
                   [{'speaker': 'host', 'source': 'x' * 2000}] * 4,
                   [{'speaker': 'host', 'source': 'x', 'replies': []}],
                   [{'source': 'x'}]]
        for context in invalid:
            with self.subTest(context_type=type(context).__name__):
                socket = Socket(dict(self.start, context=context))
                await self.server.handle(socket)
                self.assertEqual(socket.sent[-1]['type'], 'error')
        self.assertEqual(self.calls, 0)

    async def test_context_passed_and_default_empty(self):
        context = [{'speaker': 'guest', 'source': '你' * 2000}] * 3
        socket = Socket(dict(self.start, context=context))
        socket.incoming.put_nowait('{"type":"end"}')
        await self.server.handle(socket)
        self.assertEqual(self.pipeline.context, context)
        socket = Socket(self.start)
        socket.incoming.put_nowait('{"type":"end"}')
        await self.server.handle(socket)
        self.assertEqual(self.pipeline.context, [])

    async def test_handshake_limit_is_utf8_bytes(self):
        socket = Socket(self.start)
        await socket.incoming.get()
        oversized = json.dumps(dict(self.start, padding='你' * 11000), ensure_ascii=False)
        self.assertLess(len(oversized), MAX_HANDSHAKE)
        socket.incoming.put_nowait(oversized)
        await self.server.handle(socket)
        self.assertEqual(self.calls, 0)
        self.assertEqual(socket.sent[-1]['type'], 'error')

    async def test_audio_and_end(self):
        socket = Socket(self.start)
        socket.incoming.put_nowait(b'\0\0')
        socket.incoming.put_nowait('{"type":"end"}')
        await self.server.handle(socket)
        self.assertEqual(self.pipeline.audio, [b'\0\0'])
        self.assertEqual(self.pipeline.speaker, 'guest')
        self.assertEqual(self.pipeline.context, [])
        self.assertEqual(socket.sent, [{'type': 'completed'}])
        self.assertTrue(socket.closed)
    async def test_stop_cancels_capture(self):
        socket = Socket(self.start)
        task = asyncio.create_task(self.server.handle(socket))
        await self.pipeline.started.wait()
        socket.incoming.put_nowait('{"type":"stop"}')
        await task
        self.assertTrue(self.pipeline.cancelled)
    async def test_second_session_is_rejected(self):
        first = Socket(self.start)
        task = asyncio.create_task(self.server.handle(first))
        await self.pipeline.started.wait()
        second = Socket(self.start)
        await self.server.handle(second)
        self.assertEqual(self.calls, 1)
        self.assertEqual(second.sent[-1]['type'], 'error')
        first.incoming.put_nowait('{"type":"stop"}')
        await task
    async def test_real_loopback_socket_with_synthetic_pipeline(self):
        from websockets.asyncio.server import serve
        from websockets.asyncio.client import connect
        async with serve(self.server.handle, '127.0.0.1', 0, origins=[None], max_size=MAX_HANDSHAKE) as server:
            port = server.sockets[0].getsockname()[1]
            async with connect(f'ws://127.0.0.1:{port}', proxy=None) as client:
                context = [{'speaker': 'host', 'source': 'x' * 2000}] * 3
                await client.send(json.dumps(dict(self.start, context=context)))
                await client.send(b'\0\0')
                await client.send('{"type":"end"}')
                result = json.loads(await client.recv())
                self.assertEqual(result, {'type': 'completed'})
        self.assertEqual(self.pipeline.audio, [b'\0\0'])
        self.assertEqual(self.pipeline.context, context)

    async def test_oversized_audio_still_stops_at_4800_bytes(self):
        socket = Socket(self.start)
        socket.incoming.put_nowait(b'\0' * 4802)
        await self.server.handle(socket)
        self.assertEqual(self.pipeline.audio, [])
        self.assertTrue(self.pipeline.cancelled)
        self.assertEqual(socket.sent[-1]['type'], 'error')

    async def test_bad_pcm_stops_capture(self):
        socket = Socket(self.start)
        socket.incoming.put_nowait(b'odd')
        await self.server.handle(socket)
        self.assertTrue(self.pipeline.cancelled)
        self.assertTrue(socket.closed)


if __name__ == '__main__':
    unittest.main()
