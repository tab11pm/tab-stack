// Exercise real IPC handlers and shader composition with a controlled native overlay bridge.
import { installOverlayBridge, updateOutputState } from 'shoji_wm';
import { registerScreenShaderIpc, stopRetroScreen, stopScreenEffects } from '../src/effect/retro-screen.ts';

function assert(value, message) { if (!value) throw new Error(message); }
const handlers = new Map();
const events = [];
registerScreenShaderIpc({ handle: (method, fn) => handlers.set(method, fn), broadcast: (method, value) => events.push({ method, value }) }, () => null);
const call = (method, params) => handlers.get(method)(params);
const settle = async () => { await new Promise(resolve => setTimeout(resolve, 20)); };
const overlays = new Map();
let id = 0, fail = false;
installOverlayBridge({
    createOverlay(output, placement, duration, effect) {
        if (fail) throw new Error('test: GPU unavailable');
        const key = ++id;
        let close;
        const closed = new Promise(resolve => { close = resolve; });
        overlays.set(key, { output, effect, close, closed });
        return key;
    },
    waitOverlay: () => Promise.resolve(),
    waitOverlayClosed: key => overlays.get(key).closed,
    updateOverlay: (key, effect) => { if (overlays.has(key)) overlays.get(key).effect = effect; },
    disposeOverlay: key => { const value = overlays.get(key); overlays.delete(key); value?.close(); }
});
const output = { position: { x: 0, y: 0 }, resolution: { width: 1920, height: 1080 }, scale: 1, availableModes: [] };
updateOutputState({ 'DP-1': output, 'HDMI-A-1': output });
assert(call('night-light.get').enabled === false, 'default off');
call('night-light.set', { enabled: true, temperature: 4000 });
await settle();
assert(overlays.size === 2, 'night filter covers both outputs');
for (const value of overlays.values()) {
    assert(JSON.stringify(value.effect).includes('night-color.frag'), 'night stage is present');
}
const gains = () => [...overlays.values()][0].effect.pipeline.at(-1).uniforms.night_gains;
assert(gains()[0] === 1 && gains()[1] < 1 && gains()[2] < gains()[1], 'warm filter reduces blue more than green');
const blueAt4000 = gains()[2];
const count = id;
call('night-light.set', { enabled: true, temperature: 2500 });
await settle();
assert(id === count, 'temperature updates existing overlays');
assert(gains()[2] < blueAt4000, 'lower temperature makes the screen warmer');
call('night-light.set', { enabled: true, temperature: 6500 });
assert(gains().every(value => value === 1), '6500 K is neutral');
call('night-light.set', { enabled: true, temperature: 4000 });
for (const effect of ['retro', 'aquarium']) {
    call('screen-shaders.preview', { id: effect, session: 'test' });
    call('screen-shaders.apply');
    await settle();
    assert(overlays.size === 2, 'effect and night filter share one overlay per output');
    for (const value of overlays.values()) {
        const text = JSON.stringify(value.effect);
        assert(text.includes('night-color.frag'), 'night filter survives effect change');
        assert(text.includes(effect === 'retro' ? 'retro-screen.frag' : 'aquarium-water.frag'), 'selected effect survives');
    }
}
call('night-light.set', { enabled: false, temperature: 4000 });
await settle();
assert(overlays.size === 2, 'disabling night filter preserves selected screen effect');
assert(gains().every(value => value === 1), 'disabled filter restores all channels');
stopRetroScreen();
await settle();
assert(overlays.size === 0, 'neutral screen releases overlays');
call('night-light.set', { enabled: true, temperature: 4000 });
await settle();
updateOutputState({ 'DP-1': output });
stopRetroScreen();
await settle();
assert(overlays.size === 1, 'disconnected output released');
assert(call('night-light.get').enabled === true, 'hotplug preserves night mode');
stopScreenEffects();
await settle();
assert(overlays.size === 0, 'config shutdown releases night overlay');
fail = true;
call('night-light.set', { enabled: true, temperature: 4000 });
await settle();
assert(call('night-light.get').enabled === false, 'GPU failure must not report active night mode');
assert(call('night-light.get').error !== '', 'GPU failure exposed to panel');
assert(events.some(e => e.method === 'night-light.changed' && !e.value.enabled && e.value.error), 'failure broadcast');
console.log('Night light: multi-output, temperature updates, CRT/aquarium coexistence, hotplug and failure passed');
