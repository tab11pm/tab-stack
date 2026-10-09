// Source checks with a fake compositor; never connects to desktop IPC.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import vm from 'node:vm';

const source = stripTypeScriptTypes(readFileSync(new URL('../config/shojiwm/src/monitors.ts', import.meta.url), 'utf8'))
    .replace(/^import .*;$/gm, '').replace('export function', 'function');
const modes = [60, 144].map(refreshRate => ({ width: 1920, height: 1080, refreshRate }));
const outputs = ['DP-1', 'eDP-1'].map((name, i) => ({ name, enabled: true, scale: 1,
    position: { x: i * 1920, y: 0 }, resolution: { ...modes[0] }, availableModes: modes }));
const handlers = new Map();
let configure, timeout, disable, enable, persisted;
const compositor = {
    env: { get: () => '' },
    output: {
        get list() { return outputs.map(o => o.name); },
        get outputs() { return outputs; },
        get: name => outputs.find(o => o.name === name),
        configure: callback => { configure = callback; },
        reconfigure() {
            const draft = configure({ connected: outputs });
            for (const output of outputs) {
                const next = draft[output.name];
                output.scale = next.scale;
                if (next.position !== 'auto') output.position = { ...next.position };
                if (next.resolution !== 'best') output.resolution = { ...next.resolution };
            }
        },
    },
    onDisable: callback => { disable = callback; },
    onEnable: callback => { enable = callback; },
};
vm.runInNewContext(source + '\nregisterMonitors(server);', {
    COMPOSITOR: compositor,
    server: { handle: (name, callback) => handlers.set(name, callback), broadcast() {} },
    setTimeout: (callback, delay) => { assert.equal(delay, 15000); timeout = callback; return 1; },
    clearTimeout: () => { timeout = undefined; },
});
const call = (name, params) => handlers.get('monitors.' + name)(params);
const request = () => ({ primary: 'eDP-1', outputs: outputs.map(o => ({ name: o.name,
    x: o.position.x, y: o.position.y, scale: o.scale, ...o.resolution })) });

// Layout and primary selection persist without starting a mode preview.
let next = request();
next.outputs[1].y = 100;
assert.equal(call('apply-layout', next).primary, 'eDP-1');
assert.equal(outputs[1].position.y, 100);
assert.equal(timeout, undefined);

// Invalid requests must leave the live layout untouched.
for (const patch of [{ scale: 0 }, { x: NaN }, { refreshRate: 75 }]) {
    next = request(); Object.assign(next.outputs[0], patch);
    assert.throws(() => call('preview', next));
    assert.equal(outputs[0].scale, 1);
}
next = request(); next.outputs.pop();
assert.throws(() => call('preview', next));
next = request(); next.outputs[1].name = 'DP-1';
assert.throws(() => call('preview', next));

// Mode/scale changes cannot bypass preview and time out to the actual old layout.
next = request(); next.outputs[0].scale = 1.5; next.outputs[0].refreshRate = 144;
assert.throws(() => call('apply-layout', next));
assert.ok(call('preview', next).deadline > 0);
assert.equal(outputs[0].scale, 1.5);
timeout();
assert.equal(outputs[0].scale, 1);
assert.equal(outputs[0].resolution.refreshRate, 60);
assert.throws(() => call('confirm'));

// Confirmation rejects a native mismatch, but accepts a translated desktop origin.
call('preview', next);
outputs[0].scale = 1;
assert.throws(() => call('confirm'));
call('cancel');
call('preview', next);
for (const output of outputs) output.position.x += 20;
assert.equal(call('confirm').settings.outputs[0].x, 20);
assert.equal(timeout, undefined);

// Disconnected profiles survive saving and configuration reloads.
next = request();
next.outputs.push({ ...next.outputs[0], name: 'DP-9' });
call('restore', next);
assert.ok(call('apply-layout', request()).settings.outputs.some(o => o.name === 'DP-9'));
disable({ isReloading: true, persist: (_key, value) => { persisted = value; } });
enable({ isReloading: true, restore: () => persisted });
assert.ok(call('get').settings.outputs.some(o => o.name === 'DP-9'));
console.log('Monitor validation, layout, preview rollback, confirmation and reload: OK');
