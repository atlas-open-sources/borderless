export const profiles = {
  g2: {name:'Even G2', mode:'Binocular green display · concept'},
  meta: {name:'Meta Display', mode:'Taller colour display · concept'}
};
export function createSession() {
  return {epoch:1, active:false, consent:{alex:false,lin:false}, connected:{alex:true,lin:true},
    devices:{alex:'meta',lin:'g2'}, turns:[], pending:null, repliesFor:null, focused:0, selected:null, rejected:0};
}
function clearReplies(s) { s.repliesFor=null;s.focused=0;s.selected=null; }
function end(s) {s.active=false;s.epoch++;s.turns=[];s.pending=null;clearReplies(s);}
export function replyToken(s) {
 const t=s.turns.at(-1);return {id:t?.id,revision:t?.revision||1};
}
export function apply(state, event) {
  const s=structuredClone(state);
  if(event.type==='consent') { s.consent[event.person]=event.value; if(!event.value && s.active)end(s);return s; }
  if(event.type==='start') { if(s.consent.alex && s.consent.lin)s.active=true;return s; }
  if(event.type==='stop') {end(s);return s;}
  if(event.type==='device') {if(profiles[event.device])s.devices[event.person]=event.device;return s;}
  if(event.type==='connection') {s.connected[event.person]=event.value;clearReplies(s);return s;}
  if(!s.active || event.epoch!==s.epoch){s.rejected++;return s;}
  if(event.type==='partial'){s.pending=event.turn;clearReplies(s);}
  if(event.type==='final') {
    const index=s.turns.findIndex(t=>t.id===event.turn.id);
    if(index>=0 && (s.turns[index].revision||1)>=(event.turn.revision||1)){s.rejected++;return s;}
    if(index>=0)s.turns[index]=event.turn;else s.turns.push(event.turn);
    s.pending=null;clearReplies(s);
  }
  const turn=s.turns.at(-1);
  if(event.type==='assist' && turn && turn.speaker==='lin' && turn.id===event.id && !s.pending){s.repliesFor=turn.id;s.focused=0;s.selected=null;}
  if(['select','navigate','confirm'].includes(event.type)){
    const recipient=turn?.speaker==='lin'?'alex':'lin';
    const valid=turn && turn.speaker==='lin' && !s.pending && s.repliesFor===turn.id && event.id===turn.id && event.revision===(turn.revision||1)
      && (event.input!=='band' || (recipient==='alex' && s.connected.alex && s.devices.alex==='meta'));
    if(!valid){s.rejected++;return s;}
    if(event.type==='navigate' && [-1,1].includes(event.delta)){s.focused=Math.max(0,Math.min(turn.replies.length-1,s.focused+event.delta));s.selected=null;}
    if(event.type==='confirm')s.selected=s.focused;
    if(event.type==='select' && Number.isInteger(event.index) && turn.replies[event.index]){s.focused=event.index;s.selected=event.index;}
  }
  return s;
}
export function project(s, person, surface='glasses') {
  if(!s.active)return {kind:'idle',text:'Start a conversation, in either language.'};
  if(surface==='glasses' && !s.connected[person])return {kind:'offline',text:'Preview disconnected. Conversation continues on your phone.'};
  if(s.pending)return {kind:s.pending.speaker===person?'speaking':'listening',text:s.pending.speaker===person?s.pending.source:'Listening…'};
  const turn=s.turns.at(-1);
  if(!turn)return {kind:'ready',text:'A little less lost in translation.'};
  if(turn.speaker===person)return {kind:'sent',text:turn.source};
  if(person==='alex' && s.repliesFor===turn.id){
    if(s.selected!==null)return {kind:'cue',...turn.replies[s.selected],replies:turn.replies,focused:s.focused,selected:s.selected};
    return {kind:'choices',text:turn.translation,replies:turn.replies,focused:s.focused,selected:null};
  }
  return {kind:'translation',text:turn.translation,source:turn.source,turn};
}
export function benchmark(turns) {
 const rows=[];
 const check=(name,fn)=>{try{if(!fn())throw Error('Expected condition failed');rows.push({name,pass:true});}catch(e){rows.push({name,pass:false,error:e.message});}};
 const ready=()=>{let s=createSession();for(const person of ['alex','lin'])s=apply(s,{type:'consent',person,value:true});return apply(s,{type:'start'});};
 const final=(s,t)=>apply(s,{type:'final',epoch:s.epoch,turn:{...t,revision:1}});
 const assist=s=>apply(s,{type:'assist',id:s.turns.at(-1).id,epoch:s.epoch});
 const select=s=>apply(s,{type:'select',index:0,...replyToken(s),epoch:s.epoch});
 check('Both participants must consent',()=>!apply(createSession(),{type:'start'}).active);
 check('Meta host and G2 guest share one session',()=>{const s=createSession();return s.devices.alex==='meta'&&s.devices.lin==='g2';});
 check('Consent withdrawal clears the session',()=>{const s=apply(final(ready(),turns[0]),{type:'consent',person:'lin',value:false});return !s.active&&s.turns.length===0&&project(s,'alex').kind==='idle';});
 check('Spanish reaches English wearer',()=>project(final(ready(),turns[0]),'alex').text===turns[0].translation);
 check('English reaches Spanish wearer',()=>project(final(ready(),turns[1]),'lin').text===turns[1].translation);
 check('Own speech is not incoming translation',()=>project(final(ready(),turns[0]),'lin').kind==='sent');
 check('Duplicate final is rejected',()=>{let s=final(ready(),turns[0]);s=final(s,turns[0]);return s.turns.length===1&&s.rejected===1;});
 check('Stop clears both wearer views',()=>{const s=apply(final(ready(),turns[0]),{type:'stop'});return project(s,'alex').kind==='idle'&&project(s,'lin').kind==='idle';});
 check('Late result after stop is rejected',()=>{let s=ready(),epoch=s.epoch;s=apply(s,{type:'stop'});s=apply(s,{type:'final',epoch,turn:turns[0]});return s.turns.length===0&&s.rejected===1;});
 check('Disconnected display receives no transcript',()=>project(apply(final(ready(),turns[0]),{type:'connection',person:'alex',value:false}),'alex').kind==='offline');
 check('Phone-only translation works with both displays disconnected',()=>{let s=ready();for(const person of ['alex','lin'])s=apply(s,{type:'connection',person,value:false});s=final(s,turns[0]);return project(s,'alex','app').text===turns[0].translation;});
 check('Phone-only reply selection works',()=>{let s=final(ready(),turns[0]);for(const person of ['alex','lin'])s=apply(s,{type:'connection',person,value:false});s=select(assist(s));return project(s,'alex','app').kind==='cue'&&project(s,'alex').kind==='offline';});
 check('Reconnect restores latest allowed view',()=>{let s=apply(final(ready(),turns[0]),{type:'connection',person:'alex',value:false});s=final(s,turns[1]);s=apply(s,{type:'connection',person:'alex',value:true});return project(s,'alex').text===turns[1].source;});
 check('Replies visible inside app and display before selection',()=>{const s=assist(final(ready(),turns[0]));return project(s,'alex').kind==='choices'&&project(s,'alex','app').replies.length===2;});
 check('Revision invalidates reply selection',()=>{let s=select(assist(final(ready(),turns[0])));s=apply(s,{type:'final',turn:{...turns[0],revision:2},epoch:s.epoch});return s.selected===null&&s.repliesFor===null;});
 check('Old reply revision is rejected after fresh suggestions',()=>{let s=final(ready(),turns[0]),token=replyToken(s);s=apply(s,{type:'final',turn:{...turns[0],revision:2},epoch:s.epoch});s=assist(s);s=apply(s,{type:'select',index:0,...token,epoch:s.epoch});return s.selected===null&&s.rejected===1;});
 check('Band focus clamps and confirm selects without sending',()=>{let s=assist(final(ready(),turns[0]));for(const delta of [-1,1,1])s=apply(s,{type:'navigate',delta,input:'band',...replyToken(s),epoch:s.epoch});s=apply(s,{type:'confirm',input:'band',...replyToken(s),epoch:s.epoch});return s.focused===1&&s.selected===1&&s.turns.length===1;});
 check('Band navigation reopens choices after selecting a cue',()=>{let s=select(assist(final(ready(),turns[0])));s=apply(s,{type:'navigate',delta:1,input:'band',...replyToken(s),epoch:s.epoch});return s.selected===null&&s.focused===1&&project(s,'alex').kind==='choices';});
 check('Disconnected band input is rejected',()=>{let s=apply(final(ready(),turns[0]),{type:'connection',person:'alex',value:false});s=assist(s);s=apply(s,{type:'confirm',input:'band',...replyToken(s),epoch:s.epoch});return s.selected===null&&s.rejected===1;});
 check('Pending speech invalidates choices and blocks old selection',()=>{let s=assist(final(ready(),turns[0])),token=replyToken(s);s=apply(s,{type:'partial',turn:turns[1],epoch:s.epoch});s=apply(s,{type:'select',index:0,...token,epoch:s.epoch});return s.selected===null&&s.rejected===1;});
 check('Device swap preserves conversation semantics',()=>{let s=final(ready(),turns[0]),text=project(s,'alex').text;s=apply(s,{type:'device',person:'alex',device:'g2'});return project(s,'alex').text===text;});
 check('Reply selection never creates a sent utterance',()=>{const s=select(assist(final(ready(),turns[0])));return s.turns.length===1&&project(s,'alex').kind==='cue';});
 check('Guest never receives reply suggestions',()=>{const s=assist(final(ready(),turns[1]));return s.repliesFor===null&&project(s,'lin').kind==='translation'&&!project(s,'lin').replies;});
 return rows;
}

// Presentation policy; deliberately independent of device and session state.
export class ScrollFollow {
 constructor(delay=20_000) { this.delay=delay; this.following=true; this.resumeAt=null; }
 activity(now) { if(!this.following)this.resumeAt=now+this.delay; }
 scroll(distanceFromBottom,now) {
  this.following=distanceFromBottom<=32;
  this.resumeAt=this.following?null:now+this.delay;
 }
 resume() { this.following=true; this.resumeAt=null; }
 tick(now) {
  if(this.following||this.resumeAt===null||now<this.resumeAt)return false;
  this.resume(); return true;
 }
}
