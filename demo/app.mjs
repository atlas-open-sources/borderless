import {createSession,apply,project,profiles,benchmark,replyToken,ScrollFollow} from './core.mjs';
const $=id=>document.getElementById(id);
import {esc,choiceMarkup,archivedReplies,bilingualMarkup} from './render.mjs';
let fixture;
try {const r=await fetch('./fixtures.json');if(!r.ok)throw Error();fixture=await r.json();}
catch {$('stepTitle').textContent='Dialogue fixtures unavailable';$('stepDetail').textContent='Serve the demo folder over HTTP with fixtures.json present.';throw Error('Missing fixtures');}
function rehearsalSession(){let s=createSession();for(const person of ['alex','lin'])s=apply(s,{type:'consent',person,value:true});return apply(s,{type:'start'});}
let state=rehearsalSession(),cursor=0,timer=null,playing=false,lastResults=[],filter='all';
const turns=fixture.turns;
function send(e){state=apply(state,{epoch:state.epoch,...e});render();}
function pause(){clearTimeout(timer);timer=null;playing=false;}
function reset(){pause();const epoch=state.epoch+1;state=rehearsalSession();state.epoch=epoch;cursor=0;for(const entry of scrollSurfaces.values())entry.policy.resume();render();}
function assist(){const t=state.turns.at(-1);if(t)send({type:'assist',id:t.id});}
function next(){
 if(!state.active||cursor>=turns.length*2)return;
 const t=turns[Math.floor(cursor/2)];
 if(cursor%2===0)send({type:'partial',turn:{...t,source:t.source.slice(0,Math.max(4,Math.floor(t.source.length*.7)))+'…'}});
 else {send({type:'final',turn:{...t,revision:1}});assist();}
 cursor++;render();
}
function tick(){
 if(!playing||!state.active)return;
 if(cursor>=turns.length*2){pause();render();return;}
 next();
 if(cursor>=turns.length*2){pause();render();return;}
 if(cursor===2||cursor===6){timer=setTimeout(()=>{
  if(!playing||!state.active)return;
  send({type:'navigate',delta:-1,...replyToken(state),input:'app'});
  timer=setTimeout(()=>{if(!playing||!state.active)return;send({type:'confirm',...replyToken(state),input:'app'});timer=setTimeout(tick,4200);},1800);
 },2600);}else timer=setTimeout(tick,cursor%2?1500:5000);
}
function bindChoices(container,input='app'){
 const token=replyToken(state);
 container.querySelectorAll('[data-choice]').forEach(b=>b.onclick=()=>{pause();send({type:'select',index:Number(b.dataset.choice),...token,input});});
}
const scrollSurfaces=new Map();
for(const id of ['transcript','alexHud','linHud']) {
 const element=$(id), policy=new ScrollFollow();
 const entry={element,policy,lastTop:0};
 scrollSurfaces.set(id,entry);
 element.addEventListener('scroll',()=>{
  if(Math.abs(element.scrollTop-entry.lastTop)<1)return;
  entry.lastTop=element.scrollTop;
  policy.scroll(element.scrollHeight-element.clientHeight-element.scrollTop,performance.now());
 },{passive:true});
 for(const type of ['wheel','touchmove','keydown'])element.addEventListener(type,()=>policy.activity(performance.now()),{passive:true});
}
function followLatest(entry) {
 entry.policy.resume();
 entry.element.scrollTop=entry.element.scrollHeight;
 entry.lastTop=entry.element.scrollTop;
}
setInterval(()=>{
 for(const entry of scrollSurfaces.values())if(entry.policy.tick(performance.now()))followLatest(entry);
},250);
function preserveScroll(element, markup) {
 const entry=scrollSurfaces.get(element.id),top=element.scrollTop;
 element.innerHTML=markup;
 element.scrollTop=entry.policy.following?element.scrollHeight:top;
 entry.lastTop=element.scrollTop;
}
function render(){
 $('conversation').hidden=false;
 $('sessionBadge').textContent=state.active?'Conversation open':'Ready';
 $('next').disabled=!state.active||cursor>=turns.length*2;
 $('play').disabled=false;
 $('play').textContent=playing?'Pause rehearsal':cursor>=turns.length*2?'Replay rehearsal':'Play rehearsal';
 $('original').hidden=true;
 $('stepTitle').textContent=cursor>=turns.length*2?'A conversation, understood.':state.pending?`${state.pending.speaker==='lin'?'Sofía is':'You are'} speaking…`:'Say hello in Spanish';
 $('stepDetail').textContent=state.active?`Moment ${cursor} of ${turns.length*2} · scripted timing · reply choices do not send speech`:'Press Play to begin. No setup needed.';
 $('progress').innerHTML=Array.from({length:turns.length*2},(_,i)=>`<i class="${i<cursor?'done':''}"></i>`).join('');
 const latest=state.turns.at(-1);
 const transcriptMarkup=state.turns.filter(t=>filter==='all'||t.speaker===filter).map(t=>{
  const recipient=t.speaker==='lin'?'alex':'lin',view=project(state,recipient,'app');
  let replies=archivedReplies(t);
  if(t===latest&&!state.pending&&t.speaker==='lin'){
   if(state.repliesFor===t.id)replies=`<div class="replyPanel"><div class="replyHeading"><span>${recipient==='alex'?'Your reply · say it in Spanish':''}</span><span>Private suggestions</span></div><div class="replyList">${t.replies.map((r,i)=>choiceMarkup(r,i,view,'app')).join('')}</div><p class="cueNote">${state.selected!==null?'Selected as a reading cue. Speak when you are ready.':'Choose a phrase, or say something of your own. Nothing is sent.'}</p></div>`;
   else replies='<button class="helpReply" data-assist>Show reply ideas</button>';
  }
  return `<article class="turn ${t.speaker==='alex'?'hostTurn':''}"><div class="turnHead"><span class="avatar ${t.speaker==='lin'?'guest':'host'}">${t.speaker==='lin'?'S':'Y'}</span>${t.speaker==='lin'?'Sofía · Spanish → English':'You · English → Spanish'}${t.revision>1?' · revised':''}</div><div class="message">${bilingualMarkup(t)}</div>${replies}</article>`;
 }).join('')+(state.pending&&(filter==='all'||state.pending.speaker===filter)?`<article class="turn ${state.pending.speaker==='alex'?'hostTurn':''}"><div class="turnHead">${state.pending.speaker==='lin'?'Sofía':'You'} · provisional transcript</div><div class="message">${esc(state.pending.source)}</div></article>`:'');
 preserveScroll($('transcript'),transcriptMarkup);
 if(!latest&&!state.pending)$('transcript').innerHTML='<div class="emptyChat">Press Play rehearsal.<br>Sofía asks how you are. Your glasses help you reply.</div>';
 bindChoices($('transcript'));
 $('transcript').querySelector('[data-assist]')?.addEventListener('click',()=>{pause();assist();});

 for(const person of ['alex','lin']){
  const view=project(state,person),device=state.devices[person];
  $(person+'Device').value=device;
  $(person+'Profile').textContent=`${person==='alex'?'Your':'Guest'} ${profiles[device].name}`;
  $(person+'Lens').className='lens '+device;
  $(person+'Connect').textContent=`${state.connected[person]?'Disconnect':'Connect'} ${profiles[device].name} preview`;
  const labels={idle:'Waiting to begin',ready:'Ready for your conversation',offline:'Display disconnected',speaking:'Your words · provisional',listening:'Listening · simulated',sent:'Your words',translation:person==='alex'?'Sofía, in English':'Host, in Spanish',choices:person==='alex'?'Sofía, in English · choose a reply':'Host, in Spanish',cue:'Your private reading cue'};
  const entries=state.active&&state.connected[person]?state.turns:[];
  $(person+'Hud').className='hud history';
  const markup=entries.map(t=>{
   const own=t.speaker===person;
   const active=t===latest&&!state.pending&&person==='alex'&&state.repliesFor===t.id;
   const replies=active?`<div class="hudChoices"><div class="hudlabel">Your reply · private</div>${t.replies.map((r,i)=>choiceMarkup(r,i,view,'hud')).join('')}</div>`:person==='alex'?archivedReplies(t):'';
   return `<article class="hudTurn ${own?'own':''}" data-turn="${esc(t.id)}"><div class="hudlabel">${own?'You':person==='alex'?'Sofía':'Host'} · ${t.speaker==='lin'?'ES → EN':'EN → ES'}</div>${bilingualMarkup(t,true)}${replies}</article>`;
  }).join('');
  const pending=state.active&&state.connected[person]&&state.pending?`<article class="hudTurn pending"><div class="hudlabel">Listening · provisional</div><div class="hudtext">${esc(state.pending.source)}</div></article>`:'';
  preserveScroll($(person+'Hud'),markup+pending||`<div class="hudlabel">${esc(labels[view.kind])}</div><div class="hudtext">${esc(view.text)}</div>`);
  bindChoices($(person+'Hud'),'preview');
 }
 const canBand=state.active&&state.connected.alex&&state.devices.alex==='meta'&&!state.pending&&latest?.speaker==='lin'&&state.repliesFor===latest.id;
 for(const id of ['bandUp','bandDown','bandConfirm'])$(id).disabled=!canBand;
 $('phoneOnly').textContent=state.connected.alex||state.connected.lin?'Use phone only':'Show both simulated displays';
 $('phoneOnlyMobile').textContent=$('phoneOnly').textContent;
 $('privacy').textContent=state.connected.alex||state.connected.lin?'One phone · simulated displays · no audio captured':'Phone-only mode · no audio captured';
}
for(const person of ['alex','lin']){
 $(person+'Device').onchange=e=>send({type:'device',person,device:e.target.value});
 $(person+'Connect').onclick=()=>{pause();send({type:'connection',person,value:!state.connected[person]});};
}
function phoneOnly(){pause();const value=!(state.connected.alex||state.connected.lin);for(const person of ['alex','lin'])send({type:'connection',person,value});$('previews').open=value;}
$('phoneOnly').onclick=phoneOnly;$('phoneOnlyMobile').onclick=phoneOnly;
function band(type,delta){pause();send({type,delta,input:'band',...replyToken(state)});}
$('bandUp').onclick=()=>band('navigate',-1);$('bandDown').onclick=()=>band('navigate',1);$('bandConfirm').onclick=()=>band('confirm');
$('band').onkeydown=e=>{if(e.target.tagName==='BUTTON'&&e.key==='Enter')return;if(e.key==='ArrowUp'||e.key==='ArrowDown'){e.preventDefault();band('navigate',e.key==='ArrowUp'?-1:1);}if(e.key==='Enter'){e.preventDefault();band('confirm');}};
$('stop').onclick=()=>{pause();send({type:'stop'});cursor=0;render();};
$('reset').onclick=reset;$('next').onclick=()=>{pause();next();};
$('play').onclick=()=>{if(playing){pause();render();}else{if(!state.active||cursor>=turns.length*2)reset();playing=true;tick();}};
document.querySelectorAll('[data-filter]').forEach(button=>button.onclick=()=>{filter=button.dataset.filter;document.querySelectorAll('[data-filter]').forEach(b=>b.setAttribute('aria-pressed',String(b===button)));render();const entry=scrollSurfaces.get('transcript');entry.element.scrollTop=0;entry.lastTop=0;entry.policy.scroll(entry.element.scrollHeight-entry.element.clientHeight,performance.now());});
document.querySelectorAll('[data-latest]').forEach(button=>button.onclick=()=>{followLatest(scrollSurfaces.get(button.dataset.latest));});

$('benchOpen').onclick=()=>{$('lab').open=true;$('lab').scrollIntoView({behavior:'smooth'});};
$('correction').onclick=()=>{pause();const t=state.turns.at(-1);if(!state.active||!t){$('faultResult').textContent='Start and finalize a turn first.';return;}send({type:'final',turn:{...t,revision:(t.revision||1)+1,translation:t.translation+' [revised fixture]'}});$('faultResult').textContent='Revision applied. Reply choices and reading cue invalidated.';};
$('late').onclick=()=>{const before=state.rejected;send({type:'final',epoch:state.epoch-1,turn:turns[0]});$('faultResult').textContent=state.rejected>before?'Stale result rejected. No display update.':'FAIL: stale result was accepted.';};
function run(){lastResults=benchmark(turns);$('testSummary').textContent=`${lastResults.filter(r=>r.pass).length}/${lastResults.length} contract checks passed. Hardware acceptance remains open.`;$('results').innerHTML=lastResults.map(r=>`<div class="result ${r.pass?'':'fail'}">${r.pass?'✓':'×'} ${esc(r.name)}</div>`).join('');}
$('runTests').onclick=run;
$('export').onclick=()=>{run();const receipt={createdAt:new Date().toISOString(),evidence:'one-phone browser simulation only',fixtureGeneratedAt:fixture.generatedAt,model:'muse-spark-1.3',checks:lastResults,hardwareValidated:false,asrValidated:false,session:{epoch:state.epoch,turns:state.turns.length,rejected:state.rejected}};const url=URL.createObjectURL(new Blob([JSON.stringify(receipt,null,2)],{type:'application/json'}));const a=document.createElement('a');a.href=url;a.download='borderless-benchmark.json';a.click();setTimeout(()=>URL.revokeObjectURL(url),1000);};
$('provenance').textContent=`Fixtures generated ${new Date(fixture.generatedAt).toLocaleString()}. Response IDs and usage are retained in fixtures.json. No API key is shipped to this browser.`;
render();
