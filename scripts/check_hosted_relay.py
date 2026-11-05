#!/usr/bin/env python3
"""One paid end-to-end check of the hosted relay: stream a 24 kHz mono PCM16 WAV as one capture.

    python3 scripts/check_hosted_relay.py <host> <wav> host|guest

Reads the release client key from .budget/release-relay-token (never printed). Paces frames in real time, as
the app does; prints each event's type and, for turns, the source and translation. Costs one capture (~$0.02).
"""
import asyncio
import json
import sys
import uuid
import wave
from pathlib import Path

import websockets

FRAME_BYTES = 4_800
FRAME_SECONDS = FRAME_BYTES / 2 / 24_000
ROOT = Path(__file__).resolve().parents[1]


async def main(host: str, path: str, participant: str) -> int:
    key = (ROOT / ".budget" / "release-relay-token").read_text().strip()
    with wave.open(path) as audio:
        if (audio.getnchannels(), audio.getframerate(), audio.getsampwidth()) != (1, 24_000, 2):
            raise SystemExit("need 24 kHz mono 16-bit PCM")
        pcm = audio.readframes(audio.getnframes())
    async with websockets.connect(f"wss://{host}/live", open_timeout=15, max_size=65_536) as ws:
        await ws.send(json.dumps({"type": "start", "token": key, "participant": participant, "consent": True,
                                  "install_id": str(uuid.uuid4()), "language_pair": ["en", "es"]}))
        first = json.loads(await asyncio.wait_for(ws.recv(), 15))
        print("event", first.get("type"), first.get("code", ""))
        if first.get("type") != "started":
            return 1
        for start in range(0, len(pcm), FRAME_BYTES):
            await ws.send(pcm[start:start + FRAME_BYTES])
            await asyncio.sleep(FRAME_SECONDS)
        await ws.send(json.dumps({"type": "end"}))
        translated = False
        while True:
            event = json.loads(await asyncio.wait_for(ws.recv(), 90))
            kind = event.get("type")
            if kind == "turn":
                turn = event["turn"]
                translated = translated or bool(turn.get("translation"))
                print(f"turn [{event['audience']}] {turn['source']!r} -> {turn['translation']!r} replies={len(turn['replies'])}")
            else:
                print("event", kind, event.get("code", ""))
            if kind in ("stopped", "error"):
                break
    return 0 if translated else 1


if __name__ == "__main__":
    sys.exit(asyncio.run(main(*sys.argv[1:4])))
