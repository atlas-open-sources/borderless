import assert from 'node:assert/strict';
import { setupVoiceComparison } from './voice-comparison.mjs';
class Element extends EventTarget {
 constructor(voice) { super(); this.dataset={voice}; this.attrs={}; this.muted=true; }
 setAttribute(k,v) { this.attrs[k]=v; }
 click() { this.dispatchEvent(new Event('click')); }
}
const phone=new Element(), soundButton=new Element(), status=new Element();
const buttons=[new Element('original'),new Element('azure')];
const variants=[];
setupVoiceComparison({phone,buttons,soundButton,status,onVariant:v=>variants.push(v)});
soundButton.click(); assert.equal(phone.muted,false);
buttons[1].click(); assert.deepEqual(variants,['azure']); assert.equal(phone.muted,false);
assert.match(status.textContent,/real Meta/); assert.match(status.textContent,/timings differ/);
assert.equal(buttons[1].attrs['aria-pressed'],'true');
buttons[1].click(); assert.equal(variants.length,1);
buttons[0].click(); assert.deepEqual(variants,['azure','original']);
soundButton.click(); assert.equal(phone.muted,true);
console.log('Variant controls passed: correct pipeline selection, repeated click, mute preservation and disclosure');
