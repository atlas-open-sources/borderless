import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
const manifest = JSON.parse(readFileSync(new URL('../app.json', import.meta.url), 'utf8'));
const profile = readFileSync(new URL('../src/profile.ts', import.meta.url), 'utf8');
test('guest package only permits phone loopback, with no microphone capability', () => {
 assert.deepEqual(manifest.permissions.map(p => p.name), ['network']);
 assert.deepEqual(manifest.permissions[0].whitelist.sort(), ['http://127.0.0.1:8767', 'http://localhost:8767'].sort());
 assert.match(profile, /micControl: false/);
});
test('startup and companion identity match Borderless', () => {
 assert.equal(manifest.name, 'Borderless');
 assert.match(profile, /name: 'Borderless'/);
 assert.match(profile, /companionPort: 8767/);
 assert.doesNotMatch(profile, /Elsewhere/);
});
