"""CLI adapter; provider key never enters argv or logs."""
import argparse
import json
import os
import sqlite3
import sys
import urllib.error
import urllib.request
from pathlib import Path
from .core import BudgetError, Ledger, Relay
from .credentials import meta_api_key

ROOT = Path(__file__).resolve().parents[1]
# A hosted relay keeps its own ledger on a persistent volume; inherited by workers.
LEDGER = Path(os.environ.get('BORDERLESS_LEDGER') or ROOT / '.budget' / 'ledger.sqlite3')


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def transport():
    key = meta_api_key()
    if not key:
        raise BudgetError('Missing API key in project .env.')
    opener = urllib.request.build_opener(NoRedirect)

    def post(path, body):
        if path not in ('/responses', '/responses/input_tokens'):
            raise BudgetError('Endpoint is not budget-qualified.')
        req = urllib.request.Request('https://api.meta.ai/v1' + path,
            data=json.dumps(body).encode(), method='POST',
            headers={'Authorization': 'Bearer ' + key, 'Content-Type': 'application/json'})
        try:
            with opener.open(req, timeout=45) as response:
                result = json.loads(response.read(4_000_001))
                if not isinstance(result, dict):
                    raise BudgetError('Invalid provider response.')
                return result
        except urllib.error.HTTPError as error:
            raise BudgetError(f'Provider HTTP {error.code}; no automatic retry.') from None
        except (urllib.error.URLError, TimeoutError, ValueError):
            raise BudgetError('Provider unavailable or invalid response; no automatic retry.') from None
    return post


def main():
    parser = argparse.ArgumentParser(description='Meta text relay with a cumulative $20 budget')
    parser.add_argument('command', choices=['status', 'generate'])
    parser.add_argument('--max-output-tokens', type=int, default=512)
    args = parser.parse_args()
    ledger = Ledger(LEDGER)
    try:
        if args.command == 'status':
            print(json.dumps(ledger.snapshot(), indent=2))
        else:
            text = sys.stdin.read(32769)
            result = Relay(ledger, transport()).generate(text, args.max_output_tokens)
            print(json.dumps(result, ensure_ascii=False))
    except (BudgetError, OSError, sqlite3.Error) as error:
        # Never dump upstream body, request, environment or credentials.
        print(str(error) if isinstance(error, BudgetError) else
              'Local budget/key storage unavailable; stopped.', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
