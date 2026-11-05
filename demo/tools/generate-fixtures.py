"""Generate synthetic rehearsal content through the existing budgeted Meta adapter."""
import json
import sys
from datetime import datetime, timezone
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from budget_relay.core import Ledger, Relay
from budget_relay.__main__ import LEDGER, transport

turns = [
('t1','lin','你明天下午有空吗？','Are you free tomorrow afternoon?'),
('t2','alex','Yes, shall we meet at three?','可以，我们三点见面好吗？'),
('t3','lin','三点不行，四点可以。我们在咖啡馆见吧。','Three doesn’t work. Four is fine. Let’s meet at the café.'),
('t4','alex','Four works. Which café do you mean?','四点可以。你说的是哪家咖啡馆？'),
('t5','lin','地铁站旁边的那家。明天见！','The one next to the metro station. See you tomorrow!')]
relay=Relay(Ledger(LEDGER),transport())
result=[]
for tid,speaker,source,reference in turns:
    target='English' if speaker=='lin' else 'Mandarin Chinese'
    replylang='Mandarin Chinese' if speaker=='lin' else 'English'
    context='\n'.join(f"{t['speaker']}: {t['source']}" for t in result)
    prompt=f'''Conversation context (use to resolve references, times and ambiguous words):
{context}
This is synthetic, fictional demo dialogue. Return JSON only, no markdown.
Translate this {speaker} utterance into {target}: {source}
Provide two short optional replies in {replylang}. Do not claim to know the recipient's availability. Include a clarification option. Mandarin fields need tone-marked pinyin. Schema:
{{"translation":"...","sourcePinyin":"pinyin if source Chinese, otherwise empty", "replies":[{{"text":"reply in {replylang}","pinyin":"pinyin if Chinese otherwise empty","gloss":"meaning in recipient's native language ({target})"}},{{"text":"...","pinyin":"...","gloss":"..."}}]}}
Keep concise. No explanation.'''
    response=relay.generate(prompt,2048)
    raw=''.join(c.get('text','') for o in response.get('output',[]) for c in o.get('content',[]) if c.get('type')=='output_text').strip()
    if raw.startswith('```'):
        raw=raw.split('\n',1)[1].rsplit('```',1)[0].strip()
    data=json.loads(raw)
    assert isinstance(data.get('translation'),str) and len(data['replies'])==2
    assert all(all(isinstance(r.get(k),str) for k in ['text','pinyin','gloss']) for r in data['replies'])
    result.append(dict(id=tid,speaker=speaker,source=source,reference=reference,**data,
        provenance={'provider':'Meta','model':'muse-spark-1.3','responseId':response.get('id'), 'usage':response.get('usage')}))
    Path(__file__).resolve().parents[1].joinpath('fixtures.json').write_text(json.dumps({'generatedAt':datetime.now(timezone.utc).isoformat(),'mode':'Meta-generated synthetic fixture replay','turns':result},ensure_ascii=False,indent=2))
    print('Generated',tid,flush=True)
output={'generatedAt':datetime.now(timezone.utc).isoformat(),'mode':'Meta-generated synthetic fixture replay','turns':result}
Path(__file__).resolve().parents[1].joinpath('fixtures.json').write_text(json.dumps(output,ensure_ascii=False,indent=2))
print('Saved five Meta-generated fixture turns; budget:',Ledger(LEDGER).snapshot(),flush=True)
