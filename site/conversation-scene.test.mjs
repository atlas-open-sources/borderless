import assert from 'node:assert/strict';
import { describeConversationScene } from './conversation-scene.mjs';
assert.equal(describeConversationScene({phase:'speaking',speaker:'alex'}).speaker,'host');
assert.equal(describeConversationScene({phase:'speaking',speaker:'lin'}).speaker,'guest');
assert.equal(describeConversationScene({phase:'bad'}).phase,'idle');
assert.match(describeConversationScene({phase:'waiting',elapsed:2.345,latency:4.1}).detail,/2.3s.*4.1s/);
assert.match(describeConversationScene({phase:'listening'}).detail,/hardware verification/);
assert.match(describeConversationScene({phase:'selecting'}).detail,/does not speak/);
console.log('Conversation scene state checks passed');

assert.equal(describeConversationScene({phase:'ready',speaker:'host'}).title,'Sofía reads it in Spanish.');
