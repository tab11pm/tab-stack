import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const context = { module: { exports: {} } };
vm.runInNewContext(readFileSync(new URL('../config/shoji-shell/MusicSource.js', import.meta.url), 'utf8'), context);
const { selectPlayer } = context.module.exports;
const player = (name, pid, playing = true) => ({ dbusName: name, identity: 'Browser', canControl: true,
    isPlaying: playing, metadata: { 'kde:pid': pid, 'xesam:url': 'https://example.org/track' } });
const first = player('chromium.one', 100), second = player('firefox.two', 200);
assert.equal(selectPlayer([first, second], 100, false, false, ''), first);
assert.equal(selectPlayer([first, second], 0, false, false, ''), null);
assert.equal(selectPlayer([first], 0, true, false, ''), null);
assert.equal(selectPlayer([first], 0, false, true, ''), null);
assert.equal(selectPlayer([first], 200, false, false, ''), null);
first.isPlaying = false; second.isPlaying = false;
assert.equal(selectPlayer([first, second], 0, false, false, first.dbusName), first);
assert.equal(selectPlayer([first], 0, false, false, ''), first);
second.isPlaying = true;
assert.equal(selectPlayer([first, second], 0, false, false, first.dbusName), second);
assert.equal(selectPlayer([{ dbusName: 'local', canControl: true, metadata: {} }], 0, false, false, ''), null);
console.log('Music player selection, pause retention, PID matching and ambiguity: OK');
