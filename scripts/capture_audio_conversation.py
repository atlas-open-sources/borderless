"""Create a disclosed synthetic conversation through real Meta ASR/translation.

No microphone; no automatic retries. Timings start at provider readiness per turn.
Only source PCM reaches speech; script text is never supplied as transcription.
"""
import asyncio
import json
from pathlib import Path
import subprocess
import time
import wave
from budget_relay.core import Ledger
from budget_relay.async_relay import AsyncRelay
from voice_relay.transport import SpeechTransport
from conversation_relay.pipeline import SpeechConversation

ROOT = Path(__file__).resolve().parents[1]
LINES = [
    ('guest', 'Paulina (Spanish (Mexico))', 'Hola, ¿cómo estás? ¿Es tu primera vez en Madrid?'),
    ('host', 'Eddy (Spanish (Spain))', None),
    ('guest', 'Paulina (Spanish (Mexico))', 'Qué bien. Hay una cafetería muy buena en la esquina. ¿Quieres ir conmigo?'),
    ('host', 'Daniel (English (UK))', "Sorry, I don't know how to say this in Spanish, but I'm allergic to milk. Do they have oat milk?"),
    ('guest', 'Paulina (Spanish (Mexico))', 'Sí, tienen leche de avena. También podemos preguntar por las alergias. ¿Vamos?'),
    ('host', 'Eddy (Spanish (Spain))', None),
]

async def capture(out, synthesize=None):
    out.mkdir(parents=True, exist_ok=True)
    ledger = Ledger(ROOT / '.budget/ledger.sqlite3')
    before = ledger.snapshot()
    assert not before['halted'] and before['remaining_usd'] > 1
    timeline = []
    public_context = []
    cues = []
    last_guest = None
    audio = bytearray(b'\0' * 48000)  # one second ready pause
    cached = json.loads((out/'provider-evidence.json').read_text()).get('turns', []) if (out/'provider-evidence.json').exists() else []
    evidence = {'disclosure': ('Azure synthetic voices' if synthesize else 'Local synthetic Apple voices') + ', real Meta ASR and translation; explicit speaker routing, no diarization claim', 'before': before, 'turns': []}
    offset = 1.0
    for index, (speaker, voice, script) in enumerate(LINES):
        if speaker == 'host':
            if script is None:
                assert last_guest and len(last_guest['replies']) == 2
                script = last_guest['replies'][0]['text']
                cues.append({'at': round(offset - 2, 4), 'kind': 'select', 'turnID': last_guest['id'], 'index': 0, 'text': script})
            else:
                cues.append({'at': round(offset - 2, 4), 'kind': 'freeSpeech'})
        aiff, wav = out / f'voice-{index}.aiff', out / f'voice-{index}.wav'
        if index >= len(cached):
            if synthesize:
                voice = synthesize(index, speaker, script, wav)
            else:
                subprocess.run(['say', '-v', voice, '-r', '175', '-o', str(aiff), script], check=True)
                subprocess.run(['ffmpeg', '-v', 'error', '-y', '-i', str(aiff), '-ar', '24000', '-ac', '1', '-c:a', 'pcm_s16le', str(wav)], check=True)
        with wave.open(str(wav)) as stream:
            pcm = stream.readframes(stream.getnframes())
        pcm += bytes(24000)  # half-second endpointing silence
        assert len(pcm) / 48000 < 15
        events = []
        started = None
        class BoundedText:
            calls = 0
            async def generate(self, prompt, max_output_tokens=1024):
                self.calls += 1
                assert self.calls <= 3
                return await AsyncRelay().generate(prompt, max_output_tokens)
        async def frames():
            for pos in range(0, len(pcm), 4800):
                yield pcm[pos:pos+4800]
        async def emit(event):
            nonlocal started
            if event['type'] == 'started': started = time.monotonic()
            at = 0 if started is None else time.monotonic() - started
            events.append({'at': at, 'event': event})
        relay = BoundedText()
        pipeline = SpeechConversation(SpeechTransport(ledger, max_seconds=18), relay)
        if index < len(cached):
            assert cached[index]['input_script'] == script, 'Cached speech does not match the selected reply'
            voice = cached[index]['voice']
            events = cached[index]['events']
            relay.calls = cached[index]['text_calls']
        else:
            async with asyncio.timeout(90):
                await pipeline.run(frames(), emit, source=f'generated-demo-{index}', consent=True,
                                   participant=lambda _: speaker, context=public_context[-6:])
        finals = [e for e in events if e['event']['type'] == 'turn' and e['event']['audience'] == 'host']
        assert finals, 'No recognized speech'
        for item in events:
            event = item['event']
            if event.get('audience') != 'host' or event['type'] not in ('turn', 'partial'): continue
            t = event['turn']
            turn = {k: t[k] for k in ('source', 'translation', 'replies', 'revision')}
            if event['type'] == 'turn' and t.get('source_language'):
                turn['sourceLanguage'] = t['source_language']
            turn.update(id=f"audio-{index}-{t['id']}", speaker='alex' if speaker == 'host' else 'lin')
            if event['type'] == 'turn' and speaker == 'guest': last_guest = turn
            timeline.append({'at': round(offset + item['at'], 4), 'turn': turn, 'final': event['type'] == 'turn'})
        for final in finals:
            public_context.append({'speaker': speaker, 'source': final['event']['turn']['source']})
        duration = max(len(pcm)/48000, max(e['at'] for e in finals)) + 4.0
        audio.extend(pcm)
        audio.extend(bytes(max(0, int(duration*24000)*2-len(pcm))))
        evidence['turns'].append({'speaker':speaker,'voice':voice,'input_script':script,'audio_start':offset,'events':events,'text_calls':relay.calls})
        offset = len(audio)/48000
        (out/'provider-evidence.json').write_text(json.dumps(evidence,ensure_ascii=False,indent=2))
        print(f'Completed audio turn {index+1}: {len(events)} provider pipeline events', flush=True)
    evidence['after'] = ledger.snapshot()
    (out/'provider-evidence.json').write_text(json.dumps(evidence,ensure_ascii=False,indent=2))
    payload = {'duration':offset+2,'events':timeline,'cues':cues}
    (out/'audio-conversation.json').write_text(json.dumps(payload,ensure_ascii=False,indent=2))
    with wave.open(str(out/'audio-conversation.wav'),'wb') as w:
        w.setnchannels(1);w.setsampwidth(2);w.setframerate(24000);w.writeframes(audio+bytes(96000))
    print(json.dumps({'duration':offset+2,'events':len(timeline),'before':before,'after':evidence['after']}))

if __name__ == '__main__':
    import sys
    asyncio.run(capture(Path(sys.argv[1]).resolve()))
