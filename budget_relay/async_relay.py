"""Cancellable, server-only bridge to the existing metered text adapter.

A short-lived process owns HTTP calls. Cancellation terminates it and waits for
exit, leaving any ambiguous ledger reservation intact. No client holds the key.
"""
import asyncio
import json
from pathlib import Path
import sys
from .core import BudgetError

MAX_RESULT_BYTES = 65_536


class AsyncRelay:
    async def generate(self, prompt, max_output_tokens=1024):
        if not isinstance(prompt, str) or len(prompt.encode()) > 32768:
            raise BudgetError('Invalid prompt')
        if type(max_output_tokens) is not int or not 1 <= max_output_tokens <= 2048:
            raise BudgetError('Invalid output limit')
        process = await asyncio.create_subprocess_exec(
            sys.executable, '-m', 'budget_relay.async_relay', '--worker',
            cwd=Path(__file__).resolve().parents[1],
            stdin=asyncio.subprocess.PIPE, stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.DEVNULL, limit=MAX_RESULT_BYTES + 1)
        try:
            async with asyncio.timeout(50):
                payload = json.dumps({'prompt': prompt, 'limit': max_output_tokens}).encode()
                output, _ = await process.communicate(payload)
                if process.returncode != 0 or len(output) > MAX_RESULT_BYTES:
                    raise BudgetError('Translation failed; no automatic retry')
                result = json.loads(output)
                if not isinstance(result, dict):
                    raise BudgetError('Invalid translation result')
                return result
        except asyncio.CancelledError:
            raise
        except Exception:
            raise BudgetError('Translation failed; reservation preserved') from None
        finally:
            if process.returncode is None:
                process.kill()
            await process.wait()


def worker():
    from .core import Ledger, Relay
    from .__main__ import LEDGER, transport
    try:
        data = json.loads(sys.stdin.buffer.read(200_001))
        result = Relay(Ledger(LEDGER), transport()).generate(data['prompt'], data['limit'])
        encoded = json.dumps(result).encode()
        if len(encoded) > MAX_RESULT_BYTES:
            return 1
        sys.stdout.buffer.write(encoded)
        return 0
    except Exception:
        return 1


if __name__ == '__main__':
    sys.exit(worker() if sys.argv[1:] == ['--worker'] else 2)
