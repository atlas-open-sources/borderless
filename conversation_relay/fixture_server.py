"""Offline native wire benchmark: no keys, ledger, microphone or paid calls."""
import asyncio
import json
from pathlib import Path
from websockets.asyncio.server import serve
from .server import SessionServer, MAX_HANDSHAKE

FIXTURE_TOKEN = 'borderless-synthetic-benchmark-token-only'


class FixturePipeline:
    async def run(self, frames, emit, **kwargs):
        await emit({'type': 'started'})
        # Exercise binary input/end framing without recording or inference.
        async for frame in frames:
            pass
        fixture = json.loads((Path(__file__).resolve().parents[1] / 'demo/fixtures.json').read_text())
        for index, original in enumerate(fixture['turns']):
            turn = {key: original[key] for key in ('source', 'translation', 'replies')}
            turn.update(id=index, revision=1, status='ready',
                        speaker='host' if original['speaker'] == 'alex' else 'guest')
            pending = dict(turn, translation='', replies=[], status='pending')
            await emit({'type': 'partial', 'audience': 'host', 'turn': pending})
            await emit({'type': 'partial', 'audience': 'guest', 'turn': dict(pending)})
            await emit({'type': 'turn', 'audience': 'host', 'turn': turn})
            await emit({'type': 'turn', 'audience': 'guest', 'turn': dict(turn, replies=[])})
        await emit({'type': 'completed'})
        await emit({'type': 'stopped'})


async def main():
    server = SessionServer(FIXTURE_TOKEN, FixturePipeline)
    async with serve(server.handle, '127.0.0.1', 8766, origins=[None], max_size=MAX_HANDSHAKE):
        print('Synthetic fixture relay ready on 8766; no API calls', flush=True)
        await asyncio.Event().wait()


if __name__ == '__main__':
    asyncio.run(main())
