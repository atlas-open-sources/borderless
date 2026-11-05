"""Persistent, fail-closed spend accounting in integer nanodollars."""
from contextlib import contextmanager
import sqlite3
import uuid
from pathlib import Path

DOLLAR = 1_000_000_000
CAP = 20 * DOLLAR
MODEL = 'muse-spark-1.3'
INPUT_RATE = 1250  # $1.25 / million tokens, in nanodollars per token
OUTPUT_RATE = 4250
MAX_INPUT = 16384
MAX_OUTPUT = 2048


class BudgetError(RuntimeError):
    pass


def integer(value):
    if type(value) is not int or value < 0:
        raise BudgetError('Invalid or missing usage; reservation retained.')
    return value


class Ledger:
    def __init__(self, path):
        self.path = Path(path)

    def initialize(self):
        # Explicit, exclusive creation only; never reset an existing ledger.
        self.path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        fd = self.path.open('xb')
        fd.close()
        self.path.chmod(0o600)
        with self.connect() as db:
            db.executescript('''
                CREATE TABLE policy (id INTEGER PRIMARY KEY CHECK(id=1),
                    cap INTEGER NOT NULL, halted INTEGER NOT NULL);
                CREATE TABLE charges (id TEXT PRIMARY KEY, amount INTEGER NOT NULL,
                    state TEXT NOT NULL);
            ''')
            db.execute('INSERT INTO policy VALUES (1, ?, 0)', (CAP,))

    @contextmanager
    def connect(self):
        # mode=rw means a deleted/missing ledger never silently starts at zero.
        db = sqlite3.connect(self.path.resolve().as_uri() + '?mode=rw',
                             uri=True, timeout=10)
        try:
            with db:
                yield db
        finally:
            db.close()

    def snapshot(self):
        with self.connect() as db:
            cap, halted = db.execute('SELECT cap, halted FROM policy WHERE id=1').fetchone()
            used = db.execute('SELECT COALESCE(SUM(amount),0) FROM charges').fetchone()[0]
            pending = db.execute("SELECT COUNT(*) FROM charges WHERE state='reserved'").fetchone()[0]
            if cap != CAP:
                raise BudgetError('Unexpected budget policy; stopped.')
            return dict(cap_usd=cap / DOLLAR, committed_usd=used / DOLLAR,
                        remaining_usd=max(0, cap-used) / DOLLAR,
                        pending=pending, halted=bool(halted))

    def ensure_prior(self, amount):
        """Count spend recorded by another ledger against this cap. Raises, never lowers."""
        integer(amount)
        with self.connect() as db:
            db.execute('BEGIN IMMEDIATE')
            recorded, rows = db.execute(
                "SELECT COALESCE(SUM(amount),0), COUNT(*) FROM charges WHERE id LIKE 'prior:%'").fetchone()
            if amount > recorded:
                db.execute("INSERT INTO charges VALUES (?, ?, 'settled')",
                           (f'prior:{rows + 1}', amount - recorded))
            return max(amount, recorded)

    def used(self):
        """Committed plus reserved nanodollars, as an exact integer."""
        with self.connect() as db:
            return db.execute('SELECT COALESCE(SUM(amount),0) FROM charges').fetchone()[0]

    def reserve(self, amount):
        integer(amount)
        if not amount:
            raise BudgetError('Reservation must be positive.')
        with self.connect() as db:
            db.execute('BEGIN IMMEDIATE')
            cap, halted = db.execute('SELECT cap, halted FROM policy WHERE id=1').fetchone()
            used = db.execute('SELECT COALESCE(SUM(amount),0) FROM charges').fetchone()[0]
            if cap != CAP or halted or used + amount > CAP:
                raise BudgetError('Budget exhausted or halted; no inference sent.')
            ticket = uuid.uuid4().hex
            db.execute('INSERT INTO charges VALUES (?, ?, ?)', (ticket, amount, 'reserved'))
            return ticket

    def settle(self, ticket, actual):
        integer(actual)
        exceeded = False
        with self.connect() as db:
            db.execute('BEGIN IMMEDIATE')
            row = db.execute('SELECT amount,state FROM charges WHERE id=?', (ticket,)).fetchone()
            if row is None or row[1] != 'reserved':
                raise BudgetError('Unknown or already settled reservation.')
            exceeded = actual > row[0]
            db.execute("UPDATE charges SET amount=?,state='settled' WHERE id=?", (actual, ticket))
            if exceeded:
                db.execute('UPDATE policy SET halted=1 WHERE id=1')
        if exceeded:
            raise BudgetError('Provider usage exceeded reservation; ledger halted for review.')


class Relay:
    def __init__(self, ledger, post):
        self.ledger = ledger
        self.post = post

    def generate(self, text, max_output_tokens=512):
        if not isinstance(text, str) or not text.strip() or len(text.encode('utf-8')) > 32768:
            raise BudgetError('Provide 1–32768 bytes of plain text.')
        integer(max_output_tokens)
        if not 1 <= max_output_tokens <= MAX_OUTPUT:
            raise BudgetError('Output token limit must be 1–2048.')
        state = self.ledger.snapshot()
        if state['halted'] or state['remaining_usd'] <= 0:
            raise BudgetError('Budget exhausted or halted.')
        # Only stateless plain text; no hosted tools, history, media or background jobs.
        body = dict(model=MODEL, input=text, max_output_tokens=max_output_tokens,
                    store=False, stream=False, tools=[], reasoning={"effort": "minimal"})
        count = self.post('/responses/input_tokens', dict(model=MODEL, input=text))
        tokens = integer(count.get('input_tokens'))
        if tokens > MAX_INPUT:
            raise BudgetError('Input context exceeds the relay limit.')
        # Rendered context includes non-billable scaffolding. Double that estimate
        # and the full output allowance to give additional pricing/usage headroom.
        reservation = 2 * (tokens * INPUT_RATE + max_output_tokens * OUTPUT_RATE)
        ticket = self.ledger.reserve(reservation)
        # Any exception, timeout, missing usage or process death leaves full hold.
        # Never automatically retry a request with ambiguous billing outcome.
        result = self.post('/responses', body)
        usage = result.get('usage')
        if not isinstance(usage, dict):
            raise BudgetError('Missing usage; full reservation retained.')
        actual = (integer(usage.get('input_tokens')) * INPUT_RATE
                  + integer(usage.get('output_tokens')) * OUTPUT_RATE)
        # Cached input is deliberately charged at the higher normal input rate.
        self.ledger.settle(ticket, actual)
        return result
