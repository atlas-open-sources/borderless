"""Server-side bounded Meta ASR transport. No microphone or retry loop.

The injected socket contract is send(str|bytes), recv()->str|None, close().
None denotes normal provider close; every other close is an exception.
"""
import asyncio
from contextlib import asynccontextmanager
from dataclasses import dataclass
import json
import logging
import math
import time

from .core import VoiceStream, PCM_BYTES_PER_SECOND

ENDPOINT = 'wss://api.meta.ai/v1/asr/realtime'
MAX_MESSAGE_BYTES = 131_072
# How far behind real time a client's audio may arrive (cellular jitter) before the session stops.
MAX_AUDIO_LAG_SECONDS = 5
AUDIO_SECOND_NANODOLLARS = 50_000  # $0.18/hour, checked 2026-10-29


class TransportError(RuntimeError):
    pass


@dataclass(frozen=True)
class Receipt:
    bytes_sent: int
    audio_seconds: float
    completed_turns: int
    reserved_nanodollars: int
    accounting: str = 'conservative duration ceiling, not provider invoice'


@asynccontextmanager
async def meta_socket():
    from websockets.asyncio.client import connect
    from websockets.exceptions import ConnectionClosedOK
    # websockets DEBUG logging includes payloads, including the auth frame.
    logger = logging.Logger('borderless.voice.private')
    logger.disabled = True

    class NoRedirect(connect):
        def process_redirect(self, exc):
            return exc

    class Socket:
        async def send(self, message):
            await ws.send(message)

        async def recv(self):
            try:
                return await ws.recv()
            except ConnectionClosedOK as error:
                if error.rcvd is not None and error.rcvd.code == 1000:
                    return None
                raise TransportError('Unexpected provider close') from None

        async def close(self):
            await ws.close()

    async with NoRedirect(ENDPOINT, open_timeout=8, close_timeout=1,
                                  max_size=MAX_MESSAGE_BYTES, max_queue=8,
                                  write_limit=16_384, compression=None,
                                  logger=logger, proxy=None) as ws:
        yield Socket()


def project_key():
    from budget_relay.credentials import meta_api_key
    key = meta_api_key()
    if not key:
        raise TransportError('Project API key unavailable')
    return key


def decode(message):
    if not isinstance(message, str) or len(message.encode()) > MAX_MESSAGE_BYTES:
        raise TransportError('Invalid provider frame')
    value = json.loads(message)
    if not isinstance(value, dict):
        raise TransportError('Invalid provider object')
    return value


class SpeechTransport:
    def __init__(self, ledger, *, connect=meta_socket, key=project_key,
                 max_seconds=60, drain_seconds=5, io_timeout=3):
        self.core = VoiceStream(max_seconds=max_seconds, drain_seconds=drain_seconds)
        if not 0 < io_timeout <= 10:
            raise ValueError('Invalid I/O timeout')
        self.ledger = ledger
        self.connect = connect
        self.key = key
        self.io_timeout = io_timeout
        self.running = False

    async def run(self, frames, on_update, *, source, consent, on_ready=None, language_bias=None):
        """Consume PCM24k mono16 async frames with backpressure; await callbacks.

        Cancel the owning task to revoke consent. No background task survives
        return. Consumer must invalidate/clear its own output on cancellation.
        Source identity does not establish who is speaking.
        """
        if self.running:
            raise TransportError('Transport already running')
        self.running = True
        tasks = []
        phase = 'setup'
        try:
            epoch = self.core.start(source, consent=consent, now=time.monotonic())
            key = self.key()
            if not isinstance(key, str) or not key:
                raise TransportError('Project API key unavailable')
            ceiling = math.ceil(self.core.max_seconds) * AUDIO_SECOND_NANODOLLARS
            ticket = self.ledger.reserve(ceiling)
            async with asyncio.timeout(10 + self.core.max_seconds + self.core.drain_seconds):
                async with self.connect() as socket:
                    await asyncio.wait_for(socket.send(json.dumps({
                        'authorization': {'accessToken': 'Bearer ' + key},
                        'audioEncoding': 'PCM_24KHZ', 'model': 'muse-voice-transcribe-1.0',
                        'mode': 'ENDPOINTING', 'partialMode': 'CUMULATIVE',
                        'languageBias': language_bias or ['English', 'Spanish'], 'emitAudioProgress': True,
                    })), self.io_timeout)
                    del key
                    ack = decode(await asyncio.wait_for(socket.recv(), self.io_timeout))
                    if 'type' in ack or not isinstance(ack.get('sessionId'), str) or not ack['sessionId']:
                        raise TransportError('Provider handshake rejected')
                    # Only authorize client capture once the provider can consume PCM.
                    if on_ready is not None:
                        await asyncio.wait_for(on_ready(), self.io_timeout)
                    # Give input its own bounded wall-clock after handshake.
                    started = time.monotonic()
                    self.core.deadline = started + self.core.max_seconds
                    finished = asyncio.Event()
                    sent = 0
                    finals = 0

                    async def send_audio():
                        nonlocal sent
                        async with asyncio.timeout(self.core.max_seconds):
                            # Real time starts at the first frame, not at "started": a phone on cellular
                            # gets "started" one round trip later and its frames arrive with jitter.
                            first = None
                            async for frame in frames:
                                if first is None:
                                    first = time.monotonic()
                                # Never buffer an unbounded producer or burst a backlog.
                                due = first + sent / PCM_BYTES_PER_SECOND
                                await asyncio.sleep(max(0, due - time.monotonic()))
                                if time.monotonic() - due > MAX_AUDIO_LAG_SECONDS:
                                    raise TransportError('Audio source fell behind real time')
                                self.core.accept_pcm(frame, epoch=epoch, now=time.monotonic())
                                await asyncio.wait_for(socket.send(frame), self.io_timeout)
                                sent += len(frame)
                        self.core.finish_input(epoch=epoch, now=time.monotonic())
                        finished.set()
                        await asyncio.wait_for(socket.send('{"type":"endStream"}'), self.io_timeout)

                    async def receive_events():
                        nonlocal finals
                        while True:
                            message = await socket.recv()
                            if message is None:
                                if not finished.is_set():
                                    raise TransportError('Provider closed before input ended')
                                if any(not turn.complete for turn in self.core.turns.values()):
                                    raise TransportError('Provider closed with incomplete turns')
                                return
                            update = self.core.receive(decode(message), epoch=epoch, now=time.monotonic())
                            if update is not None:
                                await asyncio.wait_for(on_update(update), self.io_timeout)
                                finals += update.kind == 'final'

                    phase = 'stream'
                    sender = asyncio.create_task(send_audio())
                    receiver = asyncio.create_task(receive_events())
                    tasks = [sender, receiver]
                    # Receiver failure must stop capture immediately, not after max_seconds.
                    done, _ = await asyncio.wait(tasks, return_when=asyncio.FIRST_COMPLETED)
                    for task in done:
                        task.result()
                    if not sender.done():
                        raise TransportError('Provider closed before sender completed')
                    phase = 'drain'
                    await asyncio.wait_for(receiver, self.core.drain_seconds)
                    # Keep the full duration ceiling, rather than claim progress is an invoice.
                    self.ledger.settle(ticket, ceiling)
                    return Receipt(sent, sent / PCM_BYTES_PER_SECOND, finals, ceiling)
        except asyncio.CancelledError:
            raise
        except Exception as error:
            # Only fixed categories and numeric close codes cross this boundary.
            category = 'timeout' if isinstance(error, TimeoutError) else 'protocol'
            received = getattr(error, 'rcvd', None)
            code = getattr(received, 'code', None)
            if type(code) is int and 1000 <= code <= 4999:
                category = f'close-{code}'
            raise TransportError(f'Speech session failed ({phase}/{category}); '
                                 'no retry; reservation retained') from None
        finally:
            self.core.stop()
            for task in tasks:
                task.cancel()
            if tasks:
                await asyncio.gather(*tasks, return_exceptions=True)
            self.running = False
