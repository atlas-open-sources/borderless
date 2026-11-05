import asyncio
import json
import unittest
from unittest.mock import AsyncMock, patch
from budget_relay.async_relay import AsyncRelay
from budget_relay.core import BudgetError


class Process:
    def __init__(self, hold=False, bad=False):
        self.returncode = None
        self.hold = hold
        self.bad = bad
        self.started = asyncio.Event()
        self.killed = False
        self.waited = False
    async def communicate(self, payload):
        self.started.set()
        if self.hold:
            await asyncio.Event().wait()
        self.returncode = 1 if self.bad else 0
        return json.dumps({'output': []}).encode(), None
    def kill(self):
        self.killed = True
        self.returncode = -9
    async def wait(self):
        self.waited = True
        return self.returncode


class AsyncRelayTests(unittest.IsolatedAsyncioTestCase):
    async def test_result_and_reap(self):
        process = Process()
        with patch('asyncio.create_subprocess_exec', new=AsyncMock(return_value=process)):
            self.assertEqual(await AsyncRelay().generate('hello'), {'output': []})
        self.assertTrue(process.waited)
    async def test_cancel_kills_and_reaps_worker(self):
        process = Process(hold=True)
        with patch('asyncio.create_subprocess_exec', new=AsyncMock(return_value=process)):
            task = asyncio.create_task(AsyncRelay().generate('hello'))
            await process.started.wait()
            task.cancel()
            with self.assertRaises(asyncio.CancelledError):
                await task
        self.assertTrue(process.killed)
        self.assertTrue(process.waited)
    async def test_failure_is_sanitized(self):
        process = Process(bad=True)
        with patch('asyncio.create_subprocess_exec', new=AsyncMock(return_value=process)):
            with self.assertRaises(BudgetError):
                await AsyncRelay().generate('hello')
        self.assertTrue(process.waited)
