"""Development relay; non-loopback listening requires explicit TLS configuration."""
import argparse
import asyncio
import hmac
import ipaddress
import json
import logging
from pathlib import Path
import re
import secrets
import ssl
import time
import uuid
from budget_relay.async_relay import AsyncRelay
from budget_relay.core import Ledger
from budget_relay.__main__ import LEDGER
from voice_relay.transport import SpeechTransport
from .pipeline import SpeechConversation
from .core import validate_context
from .languages import DEFAULT_PAIR, validate_pair

ROOT = Path(__file__).resolve().parents[1]
TOKEN_PATH = ROOT / '.budget' / 'relay-token'
MAX_FRAME = 4800
MAX_HANDSHAKE = 32768
MAX_CAPACITY = 16
MAX_SESSION_SECONDS = 600
# Optional random per-install UUID from the app; older clients omit it.
INSTALL_ID = re.compile(r'[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}')
ENDED = 'Session ended; check consent, connection or relay availability.'


class Refused(Exception):
    """Refused before or during paid work, with a stable code the app can show."""
    def __init__(self, code, message):
        super().__init__(message)
        self.code = code
        self.message = message


class SessionServer:
    """capacity bounds paid sessions; admission (hosted only) applies spend and rate limits."""
    def __init__(self, token, pipeline_factory, *, capacity=1, admission=None,
                 session_seconds=None, client_address=None, log=None):
        if not isinstance(token, str) or len(token) < 32:
            raise ValueError('Strong local relay token required')
        if type(capacity) is not int or not 1 <= capacity <= MAX_CAPACITY:
            raise ValueError('Invalid session capacity')
        if session_seconds is not None and not 0 < session_seconds <= MAX_SESSION_SECONDS:
            raise ValueError('Invalid session wall-clock limit')
        self.token = token
        self.pipeline_factory = pipeline_factory
        self.capacity = capacity
        self.active = 0
        self.admission = admission
        self.session_seconds = session_seconds
        self.client_address = client_address or (lambda socket: None)
        self.log = log or (lambda **fields: None)

    async def handle(self, socket):
        tasks = []
        ticket = None
        admitted = False
        outcome = 'completed'
        reason = None
        opened = time.monotonic()
        try:
            raw = await asyncio.wait_for(socket.recv(), 5)
            if not isinstance(raw, str) or len(raw.encode("utf-8")) > MAX_HANDSHAKE:
                raise ValueError('Invalid handshake')
            start = json.loads(raw)
            if (not isinstance(start, dict) or start.get('type') != 'start' or
                    not isinstance(start.get('token'), str) or
                    not hmac.compare_digest(start['token'].encode(), self.token.encode()) or
                    start.get('participant') not in ('host', 'guest') or
                    start.get('consent') is not True):
                raise Refused('unauthorized', ENDED)
            install = start.get('install_id')
            if install is not None and (not isinstance(install, str) or not INSTALL_ID.fullmatch(install)):
                raise ValueError('Invalid install id')
            context = validate_context(start.get('context', []))
            pair = validate_pair(start.get('language_pair', DEFAULT_PAIR))
            if self.active >= self.capacity:
                raise Refused('busy', 'The translation service is busy. Try again in a minute.')
            if self.admission is not None:
                ticket = self.admission.admit(install=install, address=self.client_address(socket))
            # Synchronous check-and-claim: no await between the capacity test and this line.
            self.active += 1
            admitted = True
            frames = asyncio.Queue(maxsize=8)
            ended = False
            async def audio():
                while True:
                    value = await frames.get()
                    if value is None:
                        return
                    yield value
            async def receive():
                nonlocal ended
                while True:
                    message = await socket.recv()
                    if isinstance(message, bytes):
                        if ended or not message or len(message) % 2 or len(message) > MAX_FRAME:
                            raise ValueError('Invalid audio frame')
                        await asyncio.wait_for(frames.put(message), .5)
                    else:
                        if len(message) > 256:
                            raise ValueError('Invalid control')
                        event = json.loads(message)
                        if event == {'type': 'end'} and not ended:
                            ended = True
                            await asyncio.wait_for(frames.put(None), .5)
                        elif event == {'type': 'stop'}:
                            return
                        else:
                            raise ValueError('Invalid control')
            async def emit(event):
                await socket.send(json.dumps(event, ensure_ascii=False))
            pipeline = self.pipeline_factory()
            pipeline_options = {}
            if pair != DEFAULT_PAIR:
                pipeline_options["language_pair"] = pair
            runner = asyncio.create_task(pipeline.run(
                audio(), emit, source='phone-' + uuid.uuid4().hex,
                consent=True, participant=lambda update: start['participant'], context=context, **pipeline_options))
            reader = asyncio.create_task(receive())
            tasks = [runner, reader]
            try:
                done, _ = await asyncio.wait(tasks, timeout=self.session_seconds,
                                             return_when=asyncio.FIRST_COMPLETED)
                if not done:
                    raise Refused('time_limit', 'Session time limit reached.')
                for task in done:
                    task.result()
            finally:
                # Hold the capacity slot until capture and inference exit.
                for task in tasks:
                    if not task.done():
                        task.cancel()
                await asyncio.gather(*tasks, return_exceptions=True)

        except asyncio.CancelledError:
            outcome = 'cancelled'
            raise
        except Exception as error:
            code, message = 'ended', ENDED
            if isinstance(error, Refused):
                code, message = error.code, error.message
            outcome = code
            reason = failure_reason(error)
            try:
                await asyncio.wait_for(socket.send(json.dumps({
                    'type': 'error', 'code': code, 'message': message})), 1)
            except Exception:
                pass
        finally:
            for task in tasks:
                task.cancel()
            if tasks:
                await asyncio.gather(*tasks, return_exceptions=True)
            if admitted:
                self.active -= 1
            if ticket is not None:
                try:
                    self.admission.finish(ticket, time.monotonic() - opened)
                except Exception:
                    outcome += '/finish-failed'
            await socket.close()
            # Counters and categories only: never transcripts, audio, tokens or addresses.
            self.log(event='session', outcome=outcome, reason=reason, admitted=admitted,
                     seconds=round(time.monotonic() - opened, 1), active=self.active)


# Speech-session failures carry "(phase/category)" with fixed words only (voice_relay.transport).
TRANSPORT_CATEGORY = re.compile(r'\((setup|stream|drain)/(timeout|protocol|close-\d{4})\)')


def failure_reason(error):
    """A fixed-vocabulary reason for the session log: the exception class, plus the transport's phase/category."""
    names = []
    # The pipeline re-raises "from None"; the original stays on __context__.
    while error is not None and len(names) < 4:
        match = TRANSPORT_CATEGORY.search(str(error))
        names.append(f'{type(error).__name__}:{match.group(1)}/{match.group(2)}' if match else type(error).__name__)
        error = error.__context__
    return '<'.join(names)


def local_token():
    try:
        with open(TOKEN_PATH, 'x', opener=lambda path, flags: __import__('os').open(path, flags, 0o600)) as file:
            file.write(secrets.token_urlsafe(32))
    except FileExistsError:
        pass
    return TOKEN_PATH.read_text().strip()


def listener_arguments(parser, port):
    parser.add_argument('--bind', default='127.0.0.1')
    parser.add_argument('--port', type=int, default=port)
    parser.add_argument('--tls-cert', type=Path)
    parser.add_argument('--tls-key', type=Path)
    parser.add_argument('--behind-proxy', action='store_true',
                        help='plain listener behind a TLS-terminating proxy; trusts its X-Forwarded-For')


def check_listener(parser, options):
    try:
        address = ipaddress.ip_address(options.bind)
    except ValueError:
        parser.error('--bind must be an explicit IP address')
    if not 1 <= options.port <= 65535:
        parser.error('--port must be between 1 and 65535')
    if bool(options.tls_cert) != bool(options.tls_key):
        parser.error('Both --tls-cert and --tls-key are required')
    if options.behind_proxy and options.tls_cert:
        parser.error('--behind-proxy and TLS files are exclusive; the proxy terminates TLS')
    if not address.is_loopback and not options.tls_cert and not options.behind_proxy:
        parser.error('Non-loopback listening requires TLS certificate and key, or --behind-proxy')
    # X-Forwarded-For is trusted only behind the proxy, so never listen where clients reach us
    # directly. Inside the container 0.0.0.0 is the private Docker network (no published port).
    if options.behind_proxy and not (address.is_loopback or address.is_private):
        parser.error('--behind-proxy listens only on loopback or a private address')
    return options


def server_options(arguments=None):
    parser = argparse.ArgumentParser(description='Borderless development speech relay')
    listener_arguments(parser, 8766)
    return check_listener(parser, parser.parse_args(arguments))


async def main(options=None):
    from websockets.asyncio.server import serve
    options = options or server_options()
    context = None
    if options.tls_cert:
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.minimum_version = ssl.TLSVersion.TLSv1_2
        context.load_cert_chain(options.tls_cert, options.tls_key)
    logger = logging.Logger('borderless.local.private')
    logger.disabled = True
    ledger = Ledger(LEDGER)
    handler = SessionServer(local_token(), lambda: SpeechConversation(SpeechTransport(ledger), AsyncRelay()))
    # Default remains loopback. TLS/explicit bind must be supplied for attended phone use.
    async with serve(handler.handle, options.bind, options.port, ssl=context, origins=[None],
                     max_size=MAX_HANDSHAKE, max_queue=8, compression=None,
                     close_timeout=1, logger=logger):
        print('Borderless development relay ready', flush=True)
        await asyncio.Event().wait()


if __name__ == '__main__':
    asyncio.run(main())
