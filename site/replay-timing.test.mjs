import assert from 'node:assert/strict';
import {replayState,replayCaption} from './replay-timing.mjs';
const segments=[{start:0,end:8,index:0,speaker:'guest',speechEnd:3,resultAt:7.9,latency:4.9}];
assert.equal(replayState(segments,0,true).phase,'idle');
assert.equal(replayState(segments,2,true).phase,'speaking');
assert.deepEqual(replayState(segments,5,true),{phase:'waiting',speaker:'guest',playing:true,elapsed:2,latency:4.9,index:0});
assert.equal(replayState(segments,7.95,false).phase,'ready');
assert.equal(replayState(segments,1,false).elapsed,0);
assert.equal(replayState([],0,false).phase,'idle');
console.log('Recorded timing state: speech, measured wait, ready, pause and backwards seek passed');

const captions = [{at:1,turn:{speaker:'guest',source:'Hola'}},{at:3,turn:{speaker:'guest',source:'Hola',translation:'Hello'}},{at:4,turn:{speaker:'host',source:'Hi'}}];
assert.equal(replayCaption(captions,segments[0],0.5),undefined);
assert.equal(replayCaption(captions,segments[0],2).translation,undefined);
assert.equal(replayCaption(captions,segments[0],5).translation,'Hello');
assert.equal(replayCaption(captions,{start:4,speaker:'host'},3),undefined);
assert.equal(replayCaption(captions,{start:4,speaker:'host'},5).source,'Hi');
console.log('Bubbles preserve event timing, speaker ownership and backwards scrubbing');

assert.equal(replayCaption([{at:5,turn:{speaker:'alex',source:'Hi'}}],{start:4,speaker:'host'},6).source,'Hi');

assert.equal(replayState([...segments,{start:10,end:15,index:1,speaker:'host',speechEnd:12,resultAt:14,latency:2}],9,false).speaker,'guest');
const {readFileSync} = await import('node:fs');
for (const variant of ['original','azure']) {
  const recording = JSON.parse(readFileSync(new URL(`./assets/measured-${variant}-transcript.json`,import.meta.url)));
  for (const segment of recording.segments) {
    const translated = recording.events.filter(event => event.at >= segment.start && event.at < segment.end && event.turn.translation);
    assert.ok(translated.length);
    assert.ok(Math.abs(translated.at(-1).at - segment.resultAt) < .001);
    assert.ok(replayCaption(recording.events,segment,segment.resultAt + .001)?.translation);
  }
}
console.log('Both actual recordings preserve final translation timing; earlier partial translations are allowed');
