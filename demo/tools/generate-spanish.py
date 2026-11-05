"""Generate the short host-only Spanish rehearsal through the metered Meta adapter."""
import json, sys
from pathlib import Path
from datetime import datetime, timezone
sys.path.insert(0,str(Path(__file__).resolve().parents[2]))
from budget_relay.core import Ledger, Relay
from budget_relay.__main__ import LEDGER, transport
prompt='''Return JSON only with a turns array of exactly five fictional English/Spanish conversation turns. Exact ids/speakers/sources: t1 lin Hola, ¿cómo estás?; t2 alex I am well, thank you. And you?; t3 lin Muy bien. ¿Quieres tomar un café?; t4 alex Yes, I would like a coffee.; t5 lin Perfecto, vamos. The internal lin ID represents Spanish-speaking guest Sofia; alex is English-speaking host. Each turn needs id,speaker,source,translation,replies. Translate lin Spanish into English and alex English into Spanish. Only lin turns have two replies. Alex turns have replies:[]. Each reply has text (Spanish), gloss (English meaning), pronunciation (simple approximate English-speaker reading guide, not pinyin). First two reply meanings MUST be I'm well, thank you. And you? and Not so good today. Keep all text short, beginner-friendly, no invented place names. No markdown.'''
r=Relay(Ledger(LEDGER),transport()).generate(prompt,2048)
raw=''.join(c.get('text','') for o in r.get('output',[]) for c in o.get('content',[]) if c.get('type')=='output_text').strip()
if raw.startswith('```'): raw=raw.split('\n',1)[1].rsplit('```',1)[0]
data=json.loads(raw)
assert len(data['turns'])==5
for t in data['turns']:
 assert len(t['replies'])==(2 if t['speaker']=='lin' else 0)
 t['provenance']={'provider':'Meta','model':'muse-spark-1.3','responseId':r['id'],'usage':r['usage']}
data.update(generatedAt=datetime.now(timezone.utc).isoformat(),mode='Meta-generated Spanish synthetic fixture replay',language='es')
Path(__file__).resolve().parents[1].joinpath('fixtures.json').write_text(json.dumps(data,ensure_ascii=False,indent=2))
print('Spanish fixtures generated',Ledger(LEDGER).snapshot())
