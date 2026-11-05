"""Small paid synthetic canary; never reads microphones or real conversation."""
import json
from budget_relay.core import Ledger, Relay
from budget_relay.__main__ import LEDGER, transport
from voice_relay.core import Update
from .core import Conversation


def main():
    ledger = Ledger(LEDGER)
    session = Conversation(Relay(ledger, transport()))
    epoch = session.start('synthetic-text', 1, consent=True)
    results = []
    for turn, participant, text in [(1, 'guest', 'Hola, ¿cómo estás?'),
                                     (2, 'host', 'I am well, thank you. And you?')]:
        result = session.submit(Update('final', 1, 'synthetic-text', turn, 1, text),
                                participant, epoch=epoch)
        results.append(result)
    print(json.dumps({'evidence': 'live text API; synthetic ASR input; no microphone',
                      'turns': results, 'local_project_ledger': ledger.snapshot()}, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    try:
        main()
    except Exception:
        # Never print raw provider errors, request state or credentials.
        raise SystemExit('Canary failed; inspect local tests and budget status. No automatic retry.')
