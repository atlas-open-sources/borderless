"""Verify the separately labelled synthetic learner audition using actual Meta APIs."""
import asyncio,json,time,wave,sys
from pathlib import Path
from budget_relay.core import Ledger
from budget_relay.async_relay import AsyncRelay
from voice_relay.transport import SpeechTransport
from conversation_relay.pipeline import SpeechConversation

async def main(out):
    ledger=Ledger(Path('.budget/ledger.sqlite3'))
    before=ledger.snapshot()
    assert not before['halted'] and before['remaining_usd']>1
    with wave.open(str(out/'learner-attempt.wav')) as w: pcm=w.readframes(w.getnframes())
    duration=len(pcm)/48000
    pcm+=bytes(24000)
    async def frames():
        for i in range(0,len(pcm),4800): yield pcm[i:i+4800]
    events=[]; started=None
    async def emit(e):
        nonlocal started
        if e['type']=='started': started=time.monotonic()
        events.append({'at':0 if started is None else time.monotonic()-started,'event':e})
    async with asyncio.timeout(60):
        await SpeechConversation(SpeechTransport(ledger,max_seconds=18),AsyncRelay()).run(frames(),emit,source='learner-audition',consent=True,participant=lambda _: 'host',context=[{'speaker':'guest','source':'¿Es tu primera vez en Madrid?'}])
    finals=[e for e in events if e['event']['type']=='turn' and e['event'].get('audience')=='host']
    assert finals
    receipt={'disclosure':'Separate synthetic English-accent audition, not substituted into native recording. Actual Meta recognized text below.','duration':duration,'events':events,'before':before,'after':ledger.snapshot()}
    (out/'learner-meta-evidence.json').write_text(json.dumps(receipt,ensure_ascii=False,indent=2))
    t=finals[-1]['event']['turn']
    Path('site/assets/learner-result.json').write_text(json.dumps({'source':t['source'],'translation':t['translation'],'language':t.get('source_language'),'latency':finals[-1]['at']-duration,'disclosure':receipt['disclosure']},ensure_ascii=False,indent=2))
    print(json.dumps({'source':t['source'],'translation':t['translation'],'language':t.get('source_language'),'before':before,'after':ledger.snapshot()},ensure_ascii=False))
if __name__=='__main__': asyncio.run(main(Path(sys.argv[1])))
