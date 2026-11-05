"""Public relay limits: every cap, rate limit and the kill switch, with no provider."""
import asyncio
import contextlib
import io
import json
import os
from pathlib import Path
import sqlite3
import tempfile
import unittest
from unittest.mock import patch

from budget_relay.core import BudgetError, CAP, DOLLAR, Ledger
from budget_relay.credentials import KEY_FILE_VARIABLE, meta_api_key
from conversation_relay.hosted import (Admission, CappedRelay, Limits, address_bucket, build, forwarded_address,
                                       health_responder, hosted_options, open_ledger)
from conversation_relay.server import Refused, SessionServer, server_options

SCRATCH = Path(__file__).resolve().parents[1] / 'scratch'
SCRATCH.mkdir(exist_ok=True)
TOKEN = 'release-token-' * 4
INSTALL = '6f1c2a54-9b3e-4d7a-8c21-0e5f4b3a2d19'
OTHER_INSTALL = '0a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d'


class Clock:
    def __init__(self):
        self.now = 1_793_000_000.0

    def __call__(self):
        return self.now


class Fixture(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(dir=SCRATCH)
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.ledger, _ = open_ledger(self.root / 'ledger.sqlite3', 0)
        self.clock = Clock()
        self.key = True

    def admission(self, prior=0, **limits):
        return Admission(self.ledger, self.root / 'limits.sqlite3', Limits(**limits), prior=prior,
                         pause_file=self.root / 'paused', key_ready=lambda: self.key, clock=self.clock)

    def refused(self, admission, code, **identity):
        identity = dict(dict(install=INSTALL, address='203.0.113.7'), **identity)
        with self.assertRaises(Refused) as caught:
            admission.admit(**identity)
        self.assertEqual(caught.exception.code, code)


class LimitTests(Fixture):
    def test_defaults_and_session_ceiling(self):
        limits = Limits()
        self.assertEqual((limits.capacity, limits.audio_seconds, limits.session_seconds), (3, 60, 120))
        self.assertEqual((limits.daily_nanodollars, limits.hosted_nanodollars), (3 * DOLLAR, CAP))
        # 60 s of ASR at the duration ceiling plus 8 worst-case translation reservations.
        self.assertEqual(limits.session_ceiling, 400_312_000)

    def test_invalid_limits_rejected(self):
        for values in ({'capacity': 0}, {'capacity': 17}, {'audio_seconds': 301}, {'daily_nanodollars': True},
                       {'session_seconds': 30}, {'session_translations': -1}, {'install_sessions_per_hour': 1.5}):
            with self.subTest(values=values), self.assertRaises(ValueError):
                Limits(**values)

    def test_environment_overrides(self):
        limits = Limits.from_environment({'BORDERLESS_LIMIT_CAPACITY': '2',
                                          'BORDERLESS_LIMIT_DAILY_NANODOLLARS': str(5 * DOLLAR)})
        self.assertEqual((limits.capacity, limits.daily_nanodollars), (2, 5 * DOLLAR))
        with self.assertRaises(ValueError):
            Limits.from_environment({'BORDERLESS_LIMIT_CAPACITY': 'many'})


class CappedRelayTests(unittest.IsolatedAsyncioTestCase):
    async def test_translation_cap_per_session(self):
        class Relay:
            calls = 0
            async def generate(self, prompt, max_output_tokens=1024):
                Relay.calls += 1
                return {'ok': True}
        capped = CappedRelay(Relay(), 2)
        await capped.generate('a')
        await capped.generate('b')
        with self.assertRaises(BudgetError):
            await capped.generate('c')
        self.assertEqual(Relay.calls, 2)


class AllowanceTests(Fixture):
    def test_prior_spend_counts_against_the_same_cap_and_never_lowers(self):
        self.assertEqual(self.ledger.ensure_prior(3 * DOLLAR), 3 * DOLLAR)
        self.assertEqual(self.ledger.ensure_prior(1 * DOLLAR), 3 * DOLLAR)
        self.assertEqual(self.ledger.ensure_prior(4 * DOLLAR), 4 * DOLLAR)
        self.assertEqual(self.ledger.used(), 4 * DOLLAR)
        with self.assertRaises(BudgetError):
            self.ledger.reserve(CAP - 4 * DOLLAR + 1)
        self.ledger.reserve(CAP - 4 * DOLLAR)

    def test_reopening_keeps_the_ledger(self):
        self.ledger.reserve(DOLLAR)
        again, prior = open_ledger(self.root / 'ledger.sqlite3', 0)
        self.assertEqual(prior, 0)
        self.assertEqual(again.used(), DOLLAR)

    def test_allowance_refuses_before_the_session_could_cross_it(self):
        admission = self.admission()
        self.ledger.ensure_prior(CAP - admission.limits.session_ceiling + 1)
        self.refused(admission, 'budget')

    def test_hosted_budget_counts_only_spend_after_the_prior(self):
        self.ledger.ensure_prior(5 * DOLLAR)
        admission = self.admission(prior=5 * DOLLAR, hosted_nanodollars=DOLLAR)
        admission.finish(admission.admit(install=INSTALL, address='a'), 10)
        self.ledger.reserve(DOLLAR - admission.limits.session_ceiling + 1)
        self.refused(admission, 'budget', install=OTHER_INSTALL, address='b')

    def test_halted_ledger_refuses(self):
        ticket = self.ledger.reserve(10)
        with self.assertRaises(BudgetError):
            self.ledger.settle(ticket, 11)
        self.refused(self.admission(), 'budget')

    def test_in_flight_sessions_count_against_the_allowance(self):
        admission = self.admission(address_sessions_per_hour=99, install_sessions_per_hour=99,
                                   daily_nanodollars=CAP)
        self.ledger.ensure_prior(CAP - 2 * admission.limits.session_ceiling)
        admission.admit(install=INSTALL, address='a')
        admission.admit(install=OTHER_INSTALL, address='b')
        self.refused(admission, 'budget', address='c', install=None)


class KillSwitchTests(Fixture):
    def test_pause_file_refuses_without_redeploy(self):
        admission = self.admission()
        (self.root / 'paused').touch()
        self.refused(admission, 'paused')
        self.assertEqual(admission.status()['reason'], 'paused')
        (self.root / 'paused').unlink()
        admission.admit(install=INSTALL, address='a')

    def test_environment_pause(self):
        with patch.dict(os.environ, {'BORDERLESS_PAUSED': '1'}):
            self.refused(self.admission(), 'paused')

    def test_missing_key_refuses_cleanly(self):
        self.key = False
        admission = self.admission()
        self.refused(admission, 'unavailable')
        self.assertEqual(admission.status(), {'accepting': False, 'reason': 'unconfigured',
                                              'active': 0, 'capacity': 3})


class DailyCapTests(Fixture):
    def test_daily_cap_then_next_utc_day(self):
        admission = self.admission(daily_nanodollars=DOLLAR)
        ticket = admission.admit(install=INSTALL, address='a')
        admission.finish(ticket, 30)
        self.ledger.ensure_prior(DOLLAR - admission.limits.session_ceiling + 1)
        self.refused(admission, 'daily_cap', install=OTHER_INSTALL, address='b')
        self.clock.now += 86400
        admission.admit(install=OTHER_INSTALL, address='b')

    def test_spend_of_sessions_running_past_midnight_counts_against_the_new_day(self):
        admission = self.admission(daily_nanodollars=DOLLAR, address_sessions_per_hour=99)
        midnight = 1_793_059_200.0  # 2026-10-27 00:00 UTC
        self.clock.now = midnight - 1
        tickets = [admission.admit(install=None, address=f'a{index}') for index in range(2)]
        self.clock.now = midnight + 100
        self.ledger.ensure_prior(DOLLAR - admission.limits.session_ceiling + 1)
        for ticket in tickets:
            admission.finish(ticket, 120)
        self.refused(admission, 'daily_cap', install=None, address='b')

    def test_daily_cap_survives_restart(self):
        admission = self.admission(daily_nanodollars=DOLLAR)
        admission.admit(install=INSTALL, address='a')
        self.ledger.ensure_prior(DOLLAR)
        self.refused(self.admission(daily_nanodollars=DOLLAR), 'daily_cap', install=OTHER_INSTALL)


class RateLimitTests(Fixture):
    def test_install_sessions_per_hour(self):
        admission = self.admission(install_sessions_per_hour=2)
        for _ in range(2):
            admission.finish(admission.admit(install=INSTALL, address='a'), 5)
        self.refused(admission, 'rate_limited', address='a')
        admission.admit(install=OTHER_INSTALL, address='a')
        self.clock.now += 3601
        admission.admit(install=INSTALL, address='a')

    def test_install_seconds_per_day_and_finish_lowers_the_charge(self):
        admission = self.admission(install_seconds_per_day=120, install_sessions_per_hour=99)
        admission.finish(admission.admit(install=INSTALL, address='a'), 10.2)
        admission.finish(admission.admit(install=INSTALL, address='a'), 500)
        # 11 + 60 used; another full 60 s capture would exceed 120.
        self.refused(admission, 'rate_limited')
        self.clock.now += 86401
        admission.admit(install=INSTALL, address='a')

    def test_crash_mid_session_keeps_the_full_charge(self):
        admission = self.admission(install_seconds_per_day=119, install_sessions_per_hour=99)
        admission.admit(install=INSTALL, address='a')
        self.refused(self.admission(install_seconds_per_day=119, install_sessions_per_hour=99), 'rate_limited')

    def test_rotating_install_ids_hit_the_address_limit(self):
        admission = self.admission(address_sessions_per_hour=3)
        for index in range(3):
            admission.admit(install=f'00000000-0000-4000-8000-00000000000{index}', address='198.51.100.9')
        self.refused(admission, 'rate_limited', install='00000000-0000-4000-8000-000000000009',
                     address='198.51.100.9')
        admission.admit(install=None, address='198.51.100.10')

    def test_rotating_install_ids_cannot_raise_the_address_audio_allowance(self):
        admission = self.admission(address_seconds_per_day=180, address_sessions_per_hour=99)
        for index in range(3):
            admission.finish(admission.admit(install=f'00000000-0000-4000-8000-00000000000{index}',
                                             address='8.8.8.8'), 60)
        self.refused(admission, 'rate_limited', install='00000000-0000-4000-8000-000000000009', address='8.8.8.8')
        self.refused(admission, 'rate_limited', install=None, address='8.8.8.8')

    def test_ipv6_clients_are_limited_per_64(self):
        admission = self.admission(address_sessions_per_hour=2)
        admission.admit(install=None, address='2001:db8:1:2::1')
        admission.admit(install=None, address='2001:db8:1:2:ffff::9')
        self.refused(admission, 'rate_limited', install=None, address='2001:db8:1:2:abcd::77')
        admission.admit(install=None, address='2001:db8:1:3::1')

    def test_address_buckets(self):
        self.assertEqual(address_bucket('2001:db8:1:2:3:4:5:6'), '2001:db8:1:2::/64')
        self.assertEqual(address_bucket('::ffff:8.8.8.8'), '8.8.8.8')
        self.assertEqual(address_bucket('8.8.8.8'), '8.8.8.8')
        self.assertEqual(address_bucket(None), 'unknown')
        self.assertEqual(address_bucket('not-an-ip'), 'unknown')

    def test_old_clients_without_install_are_limited_by_address(self):
        admission = self.admission(address_sessions_per_hour=1)
        admission.admit(install=None, address='192.0.2.1')
        self.refused(admission, 'rate_limited', install=None, address='192.0.2.1')

    def test_address_seconds_per_day(self):
        admission = self.admission(address_seconds_per_day=100, address_sessions_per_hour=99)
        admission.finish(admission.admit(install=INSTALL, address='a'), 50)
        self.refused(admission, 'rate_limited', install=OTHER_INSTALL, address='a')

    def test_counters_store_no_raw_identifiers(self):
        admission = self.admission()
        admission.admit(install=INSTALL, address='203.0.113.7')
        raw = (self.root / 'limits.sqlite3').read_bytes()
        self.assertNotIn(b'203.0.113.7', raw)
        self.assertNotIn(INSTALL.encode(), raw)
        self.assertEqual((self.root / 'limits.sqlite3').stat().st_mode & 0o777, 0o600)

    def test_old_rows_are_pruned(self):
        admission = self.admission()
        admission.admit(install=INSTALL, address='a')
        self.clock.now += 3 * 86400
        admission.admit(install=INSTALL, address='a')
        with sqlite3.connect(self.root / 'limits.sqlite3') as db:
            self.assertEqual(db.execute('SELECT COUNT(*) FROM sessions').fetchone()[0], 1)


class Socket:
    def __init__(self, start, headers=None):
        self.incoming = asyncio.Queue()
        self.incoming.put_nowait(json.dumps(start))
        self.sent = []
        self.closed = False
        if headers is not None:
            self.request = type('Request', (), {'headers': headers})()
            self.remote_address = ('172.18.0.3', 5555)

    async def recv(self):
        return await self.incoming.get()

    async def send(self, value):
        self.sent.append(json.loads(value))

    async def close(self):
        self.closed = True


class Pipeline:
    def __init__(self, hold=True):
        self.started = asyncio.Event()
        self.cancelled = False
        self.hold = hold

    async def run(self, frames, emit, **kwargs):
        self.started.set()
        try:
            if self.hold:
                await asyncio.Event().wait()
            async for _ in frames:
                pass
            await emit({'type': 'completed'})
        except asyncio.CancelledError:
            self.cancelled = True
            raise


class RecordingAdmission:
    def __init__(self, refusal=None):
        self.refusal = refusal
        self.admitted = []
        self.finished = []

    def admit(self, *, install, address):
        if self.refusal:
            raise self.refusal
        self.admitted.append((install, address))
        return f'ticket-{len(self.admitted)}'

    def finish(self, ticket, elapsed):
        self.finished.append(ticket)


class HostedServerTests(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        self.pipelines = []
        self.start = dict(type='start', token=TOKEN, participant='host', consent=True, install_id=INSTALL)

    def factory(self, hold=True):
        def make():
            pipeline = Pipeline(hold)
            self.pipelines.append(pipeline)
            return pipeline
        return make

    async def test_capacity_three_then_busy(self):
        admission = RecordingAdmission()
        server = SessionServer(TOKEN, self.factory(), capacity=3, admission=admission)
        sockets = [Socket(self.start) for _ in range(3)]
        tasks = [asyncio.create_task(server.handle(socket)) for socket in sockets]
        for _ in range(50):
            await asyncio.sleep(0)
        self.assertEqual(server.active, 3)
        extra = Socket(self.start)
        await server.handle(extra)
        self.assertEqual(extra.sent[-1]['code'], 'busy')
        self.assertIn('busy', extra.sent[-1]['message'])
        self.assertEqual(len(self.pipelines), 3)
        self.assertEqual(len(admission.admitted), 3)
        for socket in sockets:
            socket.incoming.put_nowait('{"type":"stop"}')
        await asyncio.gather(*tasks)
        self.assertEqual(server.active, 0)
        self.assertEqual(sorted(admission.finished), ['ticket-1', 'ticket-2', 'ticket-3'])

    async def test_refusal_code_reaches_the_client_before_paid_work(self):
        for code in ('paused', 'unavailable', 'budget', 'daily_cap', 'rate_limited'):
            with self.subTest(code=code):
                server = SessionServer(TOKEN, self.factory(), capacity=3,
                                       admission=RecordingAdmission(Refused(code, 'x')))
                socket = Socket(self.start)
                await server.handle(socket)
                self.assertEqual(socket.sent[-1], {'type': 'error', 'code': code, 'message': 'x'})
                self.assertTrue(socket.closed)
                self.assertEqual(server.active, 0)
        self.assertEqual(self.pipelines, [])

    async def test_wall_clock_limit_cancels_the_session(self):
        admission = RecordingAdmission()
        server = SessionServer(TOKEN, self.factory(), admission=admission, session_seconds=0.05)
        socket = Socket(self.start)
        await server.handle(socket)
        self.assertEqual(socket.sent[-1]['code'], 'time_limit')
        self.assertTrue(self.pipelines[0].cancelled)
        self.assertEqual(admission.finished, ['ticket-1'])
        self.assertEqual(server.active, 0)

    async def test_install_id_is_optional_and_validated(self):
        admission = RecordingAdmission()
        server = SessionServer(TOKEN, self.factory(hold=False), admission=admission,
                               client_address=forwarded_address)
        old = dict(self.start)
        del old['install_id']
        for start in (self.start, old):
            socket = Socket(start, headers={'X-Forwarded-For': '203.0.113.7'})
            socket.incoming.put_nowait('{"type":"end"}')
            await server.handle(socket)
            self.assertEqual(socket.sent[-1], {'type': 'completed'})
        self.assertEqual(admission.admitted, [(INSTALL, '203.0.113.7'), (None, '203.0.113.7')])
        for bad in ('x' * 36, 7, INSTALL + '0', INSTALL.replace('-', ''), ''):
            socket = Socket(dict(self.start, install_id=bad))
            await server.handle(socket)
            self.assertEqual(socket.sent[-1]['code'], 'ended')
        self.assertEqual(len(admission.admitted), 2)

    async def test_unauthorized_and_malformed_starts(self):
        admission = RecordingAdmission()
        server = SessionServer(TOKEN, self.factory(), admission=admission)
        for start in (dict(self.start, token='wrong'), dict(self.start, token='ü' * 64),
                      dict(self.start, token=None), dict(self.start, consent='yes'), [1, 2], 'start'):
            socket = Socket(start)
            await server.handle(socket)
            self.assertEqual(socket.sent[-1]['type'], 'error')
        for raw in (b'\x00\x01', '{', '[]' * 20000):
            socket = Socket(self.start)
            socket.incoming = asyncio.Queue()
            socket.incoming.put_nowait(raw)
            await server.handle(socket)
            self.assertEqual(socket.sent[-1]['code'], 'ended')
        self.assertEqual(admission.admitted, [])
        self.assertEqual(self.pipelines, [])

    async def test_admission_crash_fails_closed(self):
        class Broken:
            def admit(self, **identity):
                raise sqlite3.OperationalError('disk I/O error')
        server = SessionServer(TOKEN, self.factory(), admission=Broken())
        socket = Socket(self.start)
        await server.handle(socket)
        self.assertEqual(socket.sent[-1]['code'], 'ended')
        self.assertEqual(self.pipelines, [])
        self.assertEqual(server.active, 0)

    async def test_concurrent_starts_cannot_dodge_the_in_flight_reservation(self):
        root = Path(tempfile.mkdtemp(dir=SCRATCH))
        self.addCleanup(__import__('shutil').rmtree, root)
        ledger, _ = open_ledger(root / 'ledger.sqlite3', 0)
        limits = Limits(daily_nanodollars=2 * Limits().session_ceiling, address_sessions_per_hour=99)
        admission = Admission(ledger, root / 'limits.sqlite3', limits,
                              pause_file=root / 'paused', key_ready=lambda: True)
        server = SessionServer(TOKEN, self.factory(), capacity=3, admission=admission)
        sockets = [Socket(dict(self.start, install_id=f'00000000-0000-4000-8000-00000000000{index}'))
                   for index in range(3)]
        tasks = [asyncio.create_task(server.handle(socket)) for socket in sockets]
        for _ in range(50):
            await asyncio.sleep(0)
        self.assertEqual(server.active, 2)
        self.assertEqual([socket.sent[-1]['code'] for socket in sockets if socket.sent], ['daily_cap'])
        for socket in sockets:
            socket.incoming.put_nowait('{"type":"stop"}')
        await asyncio.gather(*tasks)
        self.assertEqual(admission.holds, {})

    def test_forwarded_address_uses_the_last_hop(self):
        self.assertEqual(forwarded_address(Socket(self.start, {'X-Forwarded-For': '1.1.1.1, 203.0.113.7'})),
                         '203.0.113.7')
        self.assertEqual(forwarded_address(Socket(self.start, {})), '172.18.0.3')
        self.assertIsNone(forwarded_address(Socket(self.start)))


class OptionTests(unittest.TestCase):
    def test_behind_proxy_allows_a_plain_non_loopback_listener(self):
        options = server_options(['--bind', '0.0.0.0', '--behind-proxy'])
        self.assertTrue(options.behind_proxy)
        with contextlib.redirect_stderr(io.StringIO()):
            with self.assertRaises(SystemExit):
                server_options(['--bind', '0.0.0.0'])
            with self.assertRaises(SystemExit):
                server_options(['--behind-proxy', '--tls-cert', 'c.pem', '--tls-key', 'k.pem'])

    def test_behind_proxy_never_listens_on_a_public_address(self):
        with contextlib.redirect_stderr(io.StringIO()):
            for bind in ('8.8.8.8', '2606:4700::1111'):
                with self.subTest(bind=bind), self.assertRaises(SystemExit):
                    server_options(['--bind', bind, '--behind-proxy'])
        for bind in ('127.0.0.1', '172.18.0.2', '10.0.0.5', '0.0.0.0'):
            self.assertTrue(server_options(['--bind', bind, '--behind-proxy']).behind_proxy)

    def test_hosted_requires_proxy_or_tls_and_its_directories(self):
        common = ['--data-dir', 'd', '--secrets-dir', 's', '--control-dir', 'c']
        self.assertEqual(hosted_options(['--bind', '0.0.0.0', '--behind-proxy'] + common).port, 8080)
        with contextlib.redirect_stderr(io.StringIO()):
            for args in (common, ['--bind', '0.0.0.0'] + common, ['--behind-proxy']):
                with self.subTest(args=args), self.assertRaises(SystemExit):
                    hosted_options(args)


class CredentialTests(unittest.TestCase):
    def test_key_file_variable(self):
        with tempfile.TemporaryDirectory(dir=SCRATCH) as directory:
            path = Path(directory) / 'META_API_KEY'
            with patch.dict(os.environ, {KEY_FILE_VARIABLE: str(path)}):
                self.assertEqual(meta_api_key(), '')
                path.write_text('paste-key-here\n')
                self.assertEqual(meta_api_key(), '')
                path.write_text('synthetic-value\n')
                self.assertEqual(meta_api_key(), 'synthetic-value')


class HostedEndToEndTests(unittest.IsolatedAsyncioTestCase):
    """build() with real directories, a real WebSocket listener and no provider key."""
    async def asyncSetUp(self):
        self.temp = tempfile.TemporaryDirectory(dir=SCRATCH)
        self.addCleanup(self.temp.cleanup)
        root = Path(self.temp.name)
        self.secrets = root / 'secrets'
        self.secrets.mkdir()
        self.control = root / 'control'
        self.control.mkdir()
        self.data = root / 'data'
        environment = patch.dict(os.environ, {'BORDERLESS_PRIOR_NANODOLLARS': str(DOLLAR // 8)})
        environment.start()
        self.addCleanup(environment.stop)
        self.options = hosted_options(['--bind', '127.0.0.1', '--behind-proxy',
                                       '--data-dir', str(self.data), '--secrets-dir', str(self.secrets),
                                       '--control-dir', str(self.control)])

    async def serve(self):
        from websockets.asyncio.server import serve
        server, admission, _ = build(self.options)
        self.assertEqual(Ledger(self.data / 'ledger.sqlite3').used(), DOLLAR // 8)
        return server, admission, serve(server.handle, '127.0.0.1', 0, origins=[None],
                                        process_request=health_responder(admission))

    async def test_health_unauthenticated_and_keyless_starts(self):
        import http.client
        from websockets.asyncio.client import connect
        os.environ['BORDERLESS_RELAY_TOKEN'] = TOKEN
        server, admission, listener = await self.serve()
        async with listener as running:
            port = running.sockets[0].getsockname()[1]

            def get(path):
                connection = http.client.HTTPConnection('127.0.0.1', port, timeout=5)
                connection.request('GET', path)
                response = connection.getresponse()
                return response.status, response.read()
            status, body = await asyncio.to_thread(get, '/health')
            self.assertEqual(status, 200)
            self.assertEqual(json.loads(body), {'status': 'ok', 'accepting': False, 'reason': 'unconfigured',
                                                'active': 0, 'capacity': 3})
            self.assertNotIn(TOKEN.encode(), body)
            self.assertEqual((await asyncio.to_thread(get, '/'))[0], 404)
            start = dict(type='start', token='scanner-' * 6, participant='host', consent=True)
            async with connect(f'ws://127.0.0.1:{port}/live', proxy=None) as client:
                await client.send(json.dumps(start))
                self.assertEqual(json.loads(await client.recv())['code'], 'unauthorized')
            async with connect(f'ws://127.0.0.1:{port}/live', proxy=None) as client:
                await client.send(json.dumps(dict(start, token=TOKEN)))
                self.assertEqual(json.loads(await client.recv())['code'], 'unavailable')
            (self.secrets / 'META_API_KEY').write_text('synthetic-value')
            (self.control / 'paused').touch()
            async with connect(f'ws://127.0.0.1:{port}/live', proxy=None) as client:
                await client.send(json.dumps(dict(start, token=TOKEN)))
                self.assertEqual(json.loads(await client.recv())['code'], 'paused')
            self.assertEqual(server.active, 0)

    async def test_no_release_token_means_nobody_authenticates(self):
        (self.secrets / 'META_API_KEY').write_text('synthetic-value')
        server, admission, _ = build(self.options)
        self.assertEqual(admission.status()['reason'], 'unconfigured')
        socket = Socket(dict(type='start', token='', participant='host', consent=True))
        await server.handle(socket)
        self.assertEqual(socket.sent[-1]['code'], 'unauthorized')

    async def test_main_starts_and_serves_health(self):
        import socket as sockets
        import sys
        listener = sockets.socket()
        listener.bind(('127.0.0.1', 0))
        port = listener.getsockname()[1]
        listener.close()
        process = await asyncio.create_subprocess_exec(
            sys.executable, '-m', 'conversation_relay.hosted', '--bind', '127.0.0.1', '--port', str(port),
            '--behind-proxy', '--data-dir', str(self.data), '--secrets-dir', str(self.secrets),
            '--control-dir', str(self.control), cwd=Path(__file__).resolve().parents[1],
            stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE)
        try:
            line = await asyncio.wait_for(process.stdout.readline(), 20)
            ready = json.loads(line)
            self.assertEqual((ready['event'], ready['reason'], ready['prior_usd']), ('ready', 'unconfigured', 0.125))
            reader, writer = await asyncio.open_connection('127.0.0.1', port)
            writer.write(b'GET /health HTTP/1.1\r\nHost: x\r\n\r\n')
            await writer.drain()
            self.assertTrue((await asyncio.wait_for(reader.readline(), 5)).startswith(b'HTTP/1.1 200'))
            writer.close()
        finally:
            process.terminate()
            await process.wait()

    async def test_missing_prior_spend_refuses_to_start(self):
        with patch.dict(os.environ, {'BORDERLESS_PRIOR_NANODOLLARS': ''}):
            with self.assertRaises(SystemExit):
                build(self.options)


if __name__ == '__main__':
    unittest.main()
