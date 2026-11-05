"""Public relay: spend caps, rate limits and a kill switch in front of SessionServer.

The release app's relay token is public by nature (anyone can extract it from the
binary). It only turns away scanners; the limits here are the real protection.
State lives in SQLite on a persistent volume, so restarts never reset a counter.
"""
import argparse
import asyncio
from dataclasses import dataclass, fields
import datetime
import hashlib
import hmac
from http import HTTPStatus
import ipaddress
import json
import logging
import os
from pathlib import Path
import secrets
import sqlite3
import sys
import time
import uuid

from budget_relay.core import BudgetError, CAP, DOLLAR, INPUT_RATE, MAX_INPUT, OUTPUT_RATE, Ledger
from voice_relay.transport import AUDIO_SECOND_NANODOLLARS
from .server import MAX_HANDSHAKE, Refused, SessionServer, check_listener, listener_arguments

# Conversation.submit_async always asks for this many output tokens.
TRANSLATION_OUTPUT_TOKENS = 1024
# The most one translation can reserve under budget_relay.core.Relay's rule.
TRANSLATION_CEILING = 2 * (MAX_INPUT * INPUT_RATE + TRANSLATION_OUTPUT_TOKENS * OUTPUT_RATE)
HOUR = 3600
DAY = 86400
RETENTION = 2 * DAY
WEBSOCKET_PATH = '/live'
HEALTH_PATH = '/health'


@dataclass(frozen=True)
class Limits:
    capacity: int = 3
    audio_seconds: int = 60
    session_seconds: int = 120
    session_translations: int = 8
    install_sessions_per_hour: int = 12
    install_seconds_per_day: int = 15 * 60
    address_sessions_per_hour: int = 30
    address_seconds_per_day: int = 45 * 60
    daily_nanodollars: int = 3 * DOLLAR
    # Hosted spend on top of the seeded prior spend. Default: the whole $20 allowance decides.
    hosted_nanodollars: int = CAP

    def __post_init__(self):
        for field in fields(self):
            value = getattr(self, field.name)
            if type(value) is not int or value < 1:
                raise ValueError(f'Invalid limit {field.name}')
        if self.capacity > 16 or self.audio_seconds > 300 or self.session_seconds > 600:
            raise ValueError('Limit outside the relay bounds')
        if self.session_seconds < self.audio_seconds:
            raise ValueError('Session wall clock must cover the audio cap')

    @property
    def session_ceiling(self):
        """Worst-case nanodollars one session can reserve: full audio plus every translation."""
        return self.audio_seconds * AUDIO_SECOND_NANODOLLARS + self.session_translations * TRANSLATION_CEILING

    @classmethod
    def from_environment(cls, environ=os.environ):
        values = {}
        for field in fields(cls):
            raw = environ.get('BORDERLESS_LIMIT_' + field.name.upper())
            if raw is not None:
                values[field.name] = int(raw)
        return cls(**values)


class CappedRelay:
    """Per-session translation cap in front of the metered relay."""
    def __init__(self, relay, limit):
        self.relay = relay
        self.limit = limit
        self.calls = 0

    async def generate(self, prompt, max_output_tokens=1024):
        if self.calls >= self.limit:
            raise BudgetError('Session translation limit reached')
        self.calls += 1
        return await self.relay.generate(prompt, max_output_tokens)


class Admission:
    """Decides whether a new paid session may start; synchronous and single-process."""
    def __init__(self, ledger, path, limits, *, pause_file, key_ready, prior=0, clock=time.time):
        self.ledger = ledger
        self.path = Path(path)
        self.limits = limits
        self.pause_file = Path(pause_file)
        self.key_ready = key_ready
        self.prior = prior
        self.clock = clock
        self.holds = {}
        with self.connect() as db:
            db.executescript('''
                CREATE TABLE IF NOT EXISTS sessions (id TEXT PRIMARY KEY, install TEXT,
                    address TEXT NOT NULL, started REAL NOT NULL, seconds INTEGER NOT NULL);
                CREATE INDEX IF NOT EXISTS sessions_started ON sessions(started);
                CREATE TABLE IF NOT EXISTS days (day TEXT PRIMARY KEY, baseline INTEGER NOT NULL);
                CREATE TABLE IF NOT EXISTS marks (day TEXT PRIMARY KEY, used INTEGER NOT NULL);
                CREATE TABLE IF NOT EXISTS salt (id INTEGER PRIMARY KEY CHECK(id=1), value TEXT NOT NULL);
            ''')
            db.execute('INSERT OR IGNORE INTO salt VALUES (1, ?)', (secrets.token_hex(32),))
            self.salt = db.execute('SELECT value FROM salt').fetchone()[0].encode()
        self.path.chmod(0o600)

    def connect(self):
        db = sqlite3.connect(self.path, timeout=10, isolation_level=None)
        return Closing(db)

    def digest(self, value):
        if value is None:
            return None
        return hmac.new(self.salt, value.encode(), hashlib.sha256).hexdigest()[:32]

    def day(self, now):
        return datetime.datetime.fromtimestamp(now, datetime.timezone.utc).date().isoformat()

    def paused(self):
        return self.pause_file.exists() or os.environ.get('BORDERLESS_PAUSED') == '1'

    def status(self):
        """Health view: booleans and counts only."""
        reason = None
        if self.paused():
            reason = 'paused'
        elif not self.key_ready():
            reason = 'unconfigured'
        return {'accepting': reason is None, 'reason': reason,
                'active': len(self.holds), 'capacity': self.limits.capacity}

    def admit(self, *, install, address):
        if self.paused():
            raise Refused('paused', 'Live translation is paused right now. Try again later.')
        if not self.key_ready():
            raise Refused('unavailable', 'Live translation is not available yet.')
        now = self.clock()
        ceiling = self.limits.session_ceiling
        in_flight = sum(self.holds.values())
        state = self.ledger.snapshot()
        used = self.ledger.used()
        if (state['halted'] or used + in_flight + ceiling > CAP or
                used - self.prior + in_flight + ceiling > self.limits.hosted_nanodollars):
            raise Refused('budget', 'The live translation budget is used up.')
        day = self.day(now)
        install_key = self.digest(install)
        address_key = self.digest(address_bucket(address))
        with self.connect() as db:
            db.execute('BEGIN IMMEDIATE')
            try:
                # A day starts from the last total recorded on an earlier day, so spend of
                # sessions that ran past midnight counts against the new day.
                earlier = db.execute('SELECT used FROM marks WHERE day < ? ORDER BY day DESC LIMIT 1',
                                     (day,)).fetchone()
                start = used if earlier is None else min(used, earlier[0])
                db.execute('INSERT OR IGNORE INTO days VALUES (?, ?)', (day, start))
                db.execute('INSERT OR REPLACE INTO marks VALUES (?, ?)', (day, used))
                db.execute('COMMIT')
            except BaseException:
                db.execute('ROLLBACK')
                raise
            db.execute('BEGIN IMMEDIATE')
            try:
                db.execute('DELETE FROM sessions WHERE started < ?', (now - RETENTION,))
                db.execute('DELETE FROM marks WHERE day < ?', (self.day(now - RETENTION),))
                baseline = db.execute('SELECT baseline FROM days WHERE day=?', (day,)).fetchone()[0]
                if used - baseline + in_flight + ceiling > self.limits.daily_nanodollars:
                    raise Refused('daily_cap', "Today's live translation allowance is used up. Try again tomorrow.")
                checks = [('address', address_key, self.limits.address_sessions_per_hour,
                           self.limits.address_seconds_per_day)]
                if install_key is not None:
                    checks.insert(0, ('install', install_key, self.limits.install_sessions_per_hour,
                                      self.limits.install_seconds_per_day))
                for column, key, hourly, daily in checks:
                    count = db.execute(f'SELECT COUNT(*) FROM sessions WHERE {column}=? AND started>=?',
                                       (key, now - HOUR)).fetchone()[0]
                    seconds = db.execute(f'SELECT COALESCE(SUM(seconds),0) FROM sessions WHERE {column}=? AND started>=?',
                                         (key, now - DAY)).fetchone()[0]
                    if count >= hourly or seconds + self.limits.audio_seconds > daily:
                        raise Refused('rate_limited', 'Too many live sessions from here. Try again later.')
                ticket = uuid.uuid4().hex
                # Charge the full audio cap now; finish() lowers it to the time actually used.
                db.execute('INSERT INTO sessions VALUES (?, ?, ?, ?, ?)',
                           (ticket, install_key, address_key, now, self.limits.audio_seconds))
                db.execute('COMMIT')
            except BaseException:
                db.execute('ROLLBACK')
                raise
        # admit() never awaits, so no other admission runs between COMMIT and this line.
        self.holds[ticket] = ceiling
        return ticket

    def finish(self, ticket, elapsed):
        self.holds.pop(ticket, None)
        seconds = max(1, min(self.limits.audio_seconds, int(elapsed + 0.999)))
        used = self.ledger.used()
        with self.connect() as db:
            db.execute('UPDATE sessions SET seconds=? WHERE id=?', (seconds, ticket))
            # Only a same-day total: a finish after midnight must not hide that spend from the new day.
            day = self.day(self.clock())
            if db.execute('SELECT 1 FROM days WHERE day=?', (day,)).fetchone():
                db.execute('INSERT OR REPLACE INTO marks VALUES (?, ?)', (day, used))


class Closing:
    def __init__(self, db):
        self.db = db

    def __enter__(self):
        return self.db

    def __exit__(self, *exc):
        self.db.close()


def address_bucket(address):
    """One client controls a whole IPv6 /64, so limits apply per /64 (IPv4 per address)."""
    try:
        parsed = ipaddress.ip_address(address)
    except (TypeError, ValueError):
        return 'unknown'
    if parsed.version == 6 and parsed.ipv4_mapped is not None:
        return str(parsed.ipv4_mapped)
    if parsed.version == 6:
        return str(ipaddress.ip_network(f'{parsed}/64', strict=False))
    return str(parsed)


def read_secret(path):
    """'' when the host has not delivered the secret yet."""
    try:
        return Path(path).read_text().strip()
    except (OSError, TypeError):
        return ''


def forwarded_address(socket):
    """Caddy replaces X-Forwarded-For with the peer address; take the last hop only."""
    request = getattr(socket, 'request', None)
    value = request.headers.get('X-Forwarded-For') if request is not None else None
    if value:
        return value.split(',')[-1].strip()[:64]
    remote = getattr(socket, 'remote_address', None)
    return remote[0] if remote else None


def log_event(**values):
    print(json.dumps(dict(ts=round(time.time(), 3), **values), separators=(',', ':')), flush=True)


def hosted_options(arguments=None):
    parser = argparse.ArgumentParser(description='Borderless public speech relay (behind a TLS proxy)')
    listener_arguments(parser, 8080)
    parser.add_argument('--data-dir', type=Path, required=True)
    parser.add_argument('--secrets-dir', type=Path, required=True)
    parser.add_argument('--control-dir', type=Path, required=True)
    options = check_listener(parser, parser.parse_args(arguments))
    if not options.behind_proxy and not options.tls_cert:
        parser.error('The public relay runs behind a TLS proxy (--behind-proxy) or with TLS files')
    return options


def open_ledger(path, prior):
    """Create the hosted ledger once and count local spend against the same $20. Returns (ledger, prior)."""
    ledger = Ledger(path)
    if not ledger.path.exists():
        ledger.initialize()
    return ledger, ledger.ensure_prior(prior)


def prior_spend(environ=os.environ):
    """Local committed + pending nanodollars at deploy time, plus local headroom. Required."""
    raw = environ.get('BORDERLESS_PRIOR_NANODOLLARS')
    if raw is None or not raw.isdigit():
        raise SystemExit('BORDERLESS_PRIOR_NANODOLLARS is required; the hosted ledger must count local spend')
    return int(raw)


def health_responder(admission):
    def process_request(connection, request):
        if request.path == HEALTH_PATH:
            body = json.dumps(dict(status='ok', **admission.status()))
            response = connection.respond(HTTPStatus.OK, body + '\n')
            response.headers['Content-Type'] = 'application/json'
            response.headers['Cache-Control'] = 'no-store'
            return response
        if request.path != WEBSOCKET_PATH:
            return connection.respond(HTTPStatus.NOT_FOUND, 'Not found\n')
        return None
    return process_request


def build(options, environ=os.environ):
    from budget_relay.async_relay import AsyncRelay
    from voice_relay.transport import SpeechTransport
    from budget_relay.credentials import KEY_FILE_VARIABLE
    from .pipeline import SpeechConversation
    limits = Limits.from_environment(environ)
    options.data_dir.mkdir(parents=True, exist_ok=True, mode=0o700)
    ledger_path = options.data_dir / 'ledger.sqlite3'
    key_path = options.secrets_dir / 'META_API_KEY'
    # Inherited by AsyncRelay's worker processes, so every reservation hits this ledger.
    os.environ['BORDERLESS_LEDGER'] = str(ledger_path)
    os.environ[KEY_FILE_VARIABLE] = str(key_path)
    ledger, prior = open_ledger(ledger_path, prior_spend(environ))
    admission = Admission(ledger, options.data_dir / 'limits.sqlite3', limits, prior=prior,
                          pause_file=options.control_dir / 'paused',
                          key_ready=lambda: bool(read_secret(key_path)))
    # The release client key ships in every app, so it is plain config, not a secret.
    token = environ.get('BORDERLESS_RELAY_TOKEN', '').strip()
    if len(token) < 32:
        # No release key configured: nobody can authenticate.
        token = secrets.token_urlsafe(48)
        admission.key_ready = lambda: False

    def pipeline():
        speech = SpeechTransport(ledger, max_seconds=limits.audio_seconds)
        return SpeechConversation(speech, CappedRelay(AsyncRelay(), limits.session_translations))

    server = SessionServer(token, pipeline, capacity=limits.capacity, admission=admission,
                           session_seconds=limits.session_seconds,
                           client_address=forwarded_address if options.behind_proxy else None,
                           log=log_event)
    return server, admission, limits


async def main(arguments=None):
    from websockets.asyncio.server import serve
    options = hosted_options(arguments)
    server, admission, limits = build(options)
    logger = logging.Logger('borderless.hosted.private')
    logger.disabled = True
    async with serve(server.handle, options.bind, options.port, origins=[None],
                     process_request=health_responder(admission),
                     max_size=MAX_HANDSHAKE, max_queue=8, compression=None,
                     close_timeout=1, logger=logger):
        log_event(event='ready', session_ceiling_usd=limits.session_ceiling / DOLLAR,
                  daily_usd=limits.daily_nanodollars / DOLLAR, hosted_usd=limits.hosted_nanodollars / DOLLAR,
                  prior_usd=admission.prior / DOLLAR, **admission.status())
        await asyncio.Event().wait()


if __name__ == '__main__':
    try:
        asyncio.run(main(sys.argv[1:]))
    except KeyboardInterrupt:
        pass
