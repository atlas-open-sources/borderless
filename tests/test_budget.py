import concurrent.futures
import tempfile
import unittest
from pathlib import Path
from budget_relay.core import BudgetError, CAP, Ledger, Relay

SCRATCH = Path(__file__).resolve().parents[1] / 'scratch' / '2026-10-28' / '085402-codex-0c708c94'
SCRATCH.mkdir(parents=True, exist_ok=True)


class BudgetTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(dir=SCRATCH)
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name) / 'ledger.db'
        self.ledger = Ledger(self.path)
        self.ledger.initialize()

    def test_restart_and_exact_limit(self):
        self.ledger.reserve(CAP)
        with self.assertRaises(BudgetError):
            Ledger(self.path).reserve(1)
        self.assertEqual(Ledger(self.path).snapshot()['remaining_usd'], 0)

    def test_atomic_concurrent_reservations(self):
        def attempt(_):
            try:
                Ledger(self.path).reserve(CAP // 7)
                return 1
            except BudgetError:
                return 0
        with concurrent.futures.ThreadPoolExecutor(max_workers=12) as pool:
            self.assertEqual(sum(pool.map(attempt, range(30))), 7)
        self.assertLessEqual(self.ledger.snapshot()['committed_usd'], 20)

    def test_missing_ledger_fails_closed(self):
        with self.assertRaises(Exception):
            Ledger(Path(self.temp.name) / 'absent.db').reserve(1)
        self.assertFalse((Path(self.temp.name) / 'absent.db').exists())

    def test_cannot_reinitialize(self):
        self.ledger.reserve(1000)
        with self.assertRaises(FileExistsError):
            self.ledger.initialize()
        self.assertGreater(self.ledger.snapshot()['committed_usd'], 0)

    def test_success_settles_and_duplicates_rejected(self):
        ticket = self.ledger.reserve(10000)
        self.ledger.settle(ticket, 1000)
        with self.assertRaises(BudgetError):
            self.ledger.settle(ticket, 0)
        self.assertEqual(self.ledger.snapshot()['committed_usd'], 0.000001)

    def test_overrun_halts(self):
        ticket = self.ledger.reserve(10)
        with self.assertRaises(BudgetError):
            self.ledger.settle(ticket, 11)
        with self.assertRaises(BudgetError):
            self.ledger.reserve(1)
        self.assertTrue(self.ledger.snapshot()['halted'])

    def test_timeout_and_missing_usage_keep_hold(self):
        for failure in ['timeout', 'usage']:
            def post(path, body):
                if path.endswith('input_tokens'):
                    return {'input_tokens': 100}
                if failure == 'timeout':
                    raise TimeoutError()
                return {}
            with self.assertRaises((BudgetError, TimeoutError)):
                Relay(self.ledger, post).generate('hello')
        self.assertEqual(Ledger(self.path).snapshot()['pending'], 2)

    def test_no_inference_when_insufficient_budget(self):
        self.ledger.reserve(CAP-1)
        calls = []
        def post(path, body):
            calls.append(path)
            return {'input_tokens': 100}
        with self.assertRaises(BudgetError):
            Relay(self.ledger, post).generate('hello')
        self.assertEqual(calls, ['/responses/input_tokens'])

    def test_success_request_restrictions_and_accounting(self):
        calls = []
        def post(path, body):
            calls.append((path, body))
            if path.endswith('input_tokens'):
                return {'input_tokens': 100}
            return {'usage': {'input_tokens': 50, 'output_tokens': 20}}
        Relay(self.ledger, post).generate('hello', 100)
        self.assertEqual(calls[1][1], dict(model='muse-spark-1.3', input='hello',
            max_output_tokens=100, store=False, stream=False, tools=[], reasoning={"effort":"minimal"}))
        self.assertEqual(self.ledger.snapshot()['pending'], 0)
        self.assertEqual(self.ledger.snapshot()['committed_usd'], 0.0001475)

    def test_bad_input_never_calls_provider(self):
        def post(*args):
            self.fail('Provider called for invalid input')
        for text, limit in [('', 100), ('x', 0), ('x', True), ('x', 2049), ('界'*12000, 100)]:
            with self.assertRaises(BudgetError):
                Relay(self.ledger, post).generate(text, limit)

    def test_invalid_usage_keeps_hold(self):
        def post(path, body):
            if path.endswith('input_tokens'):
                return {'input_tokens': 100}
            return {'usage': {'input_tokens': -1, 'output_tokens': 1}}
        with self.assertRaises(BudgetError):
            Relay(self.ledger, post).generate('hello')
        self.assertEqual(self.ledger.snapshot()['pending'], 1)


if __name__ == '__main__':
    unittest.main()
