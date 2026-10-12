// Exercise the exported QML state functions without opening windows or desktop IPC.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
const source = readFileSync(new URL('../config/shoji-shell/Switcher.qml', import.meta.url), 'utf8');
const funcs = [];
for (const match of source.matchAll(/^    function \w+\([^\n]*\) \{/gm)) {
    const start = match.index;
    let depth = 1, end = start + match[0].length;
    while (depth && end < source.length) {
        if (source[end] === '{') depth++;
        if (source[end] === '}') depth--;
        end++;
    }
    funcs.push(source.slice(start, end));
}
function fixture() {
    const sent = [];
    const state = vm.createContext({ open: false, entries: [], index: -1, desiredIndex: 1,
        targetOutput: '', error: '', pendingGet: 0, sequence: 0, commitPending: false,
        socket: { connected: true, write: line => sent.push(JSON.parse(line)), flush() {} } });
    vm.runInContext(funcs.join('\n'), state);
    return { state, sent };
}
const view = { currentMonitor: 'TEST-1', monitors: [{ name: 'TEST-1', workspaces: [{ index: 1,
    windows: [{ id: 'current', focused: true, lastFocusedAt: 30 },
        { id: 'previous', focused: false, lastFocusedAt: 20 },
        { id: 'oldest', focused: false, lastFocusedAt: 10 }] }] }] };
for (const [direction, expected] of [[1, 'previous'], [-1, 'oldest']]) {
    const { state, sent } = fixture();
    state.step(direction);
    state.commit(); // Alt release can arrive while workspaces.get is in flight.
    assert.equal(state.commitPending, true);
    state.build(view);
    assert.equal(sent.at(-1).method, 'windows.activate');
    assert.equal(sent.at(-1).params.windowId, expected);
    assert.equal(state.open, false);
}
const { state, sent } = fixture();
state.step(-1); state.step(-1); state.build(view);
assert.equal(state.entries[state.index].id, 'previous');
state.cancel();
assert.equal(sent.length, 1, 'Escape must never activate a window');
state.step(1); state.build({ monitors: [] });
assert.equal(state.open, false, 'An empty desktop closes the switcher');
console.log('Switcher: forward/reverse MRU, pending release, wrap, cancel and empty desktop passed');
