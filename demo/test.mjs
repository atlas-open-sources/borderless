import {readFileSync} from 'node:fs';
import assert from 'node:assert/strict';
import {benchmark,ScrollFollow} from './core.mjs';
const fixtures=JSON.parse(readFileSync(new URL('./fixtures.json',import.meta.url)));
assert.equal(fixtures.turns.length,5);
for(const turn of fixtures.turns){
 assert.equal(turn.provenance.model,'muse-spark-1.3');
 assert.ok(turn.provenance.responseId);
 assert.equal(turn.replies.length,turn.speaker==='lin'?2:0);
 if(turn.speaker==='lin')for(const reply of turn.replies)assert.ok(reply.pronunciation.length>0);
}
assert.match(fixtures.turns[0].source,/cómo estás/i);
assert.match(fixtures.turns[0].replies[0].gloss,/well|good|fine/i);
const rows=benchmark(fixtures.turns);
for(const row of rows){console.log(`${row.pass?'PASS':'FAIL'} ${row.name}`);assert.ok(row.pass,row.name);}
console.log(`${rows.length} contract checks and fixture validation passed.`);

const follow=new ScrollFollow();
assert.equal(follow.following,true);
follow.scroll(100,0);
assert.equal(follow.following,false);
assert.equal(follow.tick(19_999),false);
follow.activity(19_000);
assert.equal(follow.tick(20_000),false);
assert.equal(follow.tick(39_000),true);
assert.equal(follow.following,true);
follow.scroll(100,40_000);
follow.scroll(0,40_001);
assert.equal(follow.following,true);
assert.equal(follow.resumeAt,null);
const independent=new ScrollFollow();
follow.scroll(200,50_000);
assert.equal(independent.following,true);
follow.resume();
assert.equal(follow.following,true);
console.log('Scroll-follow checks passed: timeout, activity renewal, bottom resume, explicit resume, independent surfaces.');

const {choiceMarkup, archivedReplies, bilingualMarkup}=await import('./render.mjs');
const bilingualTurn={speaker:'lin',source:'Hola, ¿cómo estás?',translation:'Hi, how are you?',replies:[
 {text:'Estoy bien, gracias.',gloss:'I’m well, thanks.',pronunciation:'REMOVED_PHONETIC_ONE'},
 {text:'No estoy bien.',gloss:'I’m not well.',pronunciation:'REMOVED_PHONETIC_TWO'}]};
for(const speaker of ['lin','alex']) {
 for(const hud of [true,false]) {
  const markup=bilingualMarkup({...bilingualTurn,speaker},hud);
  assert.ok(markup.includes(bilingualTurn.source));
  assert.ok(markup.includes(bilingualTurn.translation));
 }
}
for(const place of ['hud','app']) {
 const markup=bilingualMarkup(bilingualTurn,place==='hud')+bilingualTurn.replies.map((r,i)=>choiceMarkup(r,i,{focused:0,selected:null},place)).join('');
 assert.ok(markup.indexOf(bilingualTurn.source)<markup.indexOf(bilingualTurn.replies[0].text));
 for(const reply of bilingualTurn.replies) {assert.ok(markup.includes(reply.text));assert.ok(markup.includes(reply.gloss));assert.ok(!markup.includes(reply.pronunciation));}
 assert.equal((markup.match(/data-choice=/g)||[]).length,2);
}
assert.ok(!archivedReplies(bilingualTurn).includes('REMOVED_PHONETIC'));
assert.equal(archivedReplies({...bilingualTurn,speaker:'alex'}),'');
assert.ok(bilingualMarkup({source:'<script>',translation:'A & B'}).includes('&lt;script&gt;'));
console.log('Bilingual render checks passed: both languages, both complete choices below speech, no phonetics, escaped text.');
