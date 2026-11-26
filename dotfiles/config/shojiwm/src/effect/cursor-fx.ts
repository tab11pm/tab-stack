import {
  COMPOSITOR, animationVariable, createAnimationController, signal, effect, compileOverlayEffect,
  backdropSource, shaderStage, loadShader, type OverlayHandle, type PointerMoveEvent, type ShaderUniformVec2,
} from "shoji_wm";
import type { IpcServer } from "shoji_wm/ipc";

const SHADER = loadShader("./src/effect/cursor-fx.frag");
const MODES = ["none", "blob", "ring"] as const;
type Mode = typeof MODES[number];
const CLOCK = animationVariable("cursor-fx.phase");
const animation = createAnimationController(() => {});
const phase = animation.variable(CLOCK);
const modeValue = signal(0);
const smooth = signal<[number, number]>([0, 0]);
const raw = signal<[number, number]>([0, 0]);
const hotValue = signal(0);
const vec2 = (value: typeof smooth): ShaderUniformVec2 => [value(p => p[0]), value(p => p[1])];
const SMOOTH = vec2(smooth);
const RAW = vec2(raw);
const active = new Map<string, OverlayHandle>();
let mode: Mode = "none";
let hotTarget = 0;
let last = Date.now();
let error = "";
// A transparent theme hides the system pointer while the shader draws it.
const HIDDEN_THEME = "shoji-hidden-cursor";
const envTheme = COMPOSITOR.env.get("XCURSOR_THEME");
// shortcut: a reload while hidden falls back to Adwaita, store the theme if a custom one matters.
const VISIBLE_THEME = envTheme && envTheme !== HIDDEN_THEME ? envTheme : "Adwaita";
let cursorTheme = "";
let overPanel = false;
// Never start invisible: the shell re-enables the effect after a reload.
if (envTheme === HIDDEN_THEME) COMPOSITOR.cursor.configure({ theme: VISIBLE_THEME, size: 24 });

// effect() reads the clock: an unread computed stays dirty and never notifies subscribe().
effect(() => {
  phase();
  const now = Date.now();
  const k = 1 - Math.exp(-Math.min(0.1, (now - last) / 1000) * 16);
  last = now;
  const [sx, sy] = smooth.peek();
  const [rx, ry] = raw.peek();
  smooth.value = [sx + (rx - sx) * k, sy + (ry - sy) * k];
  hotValue.value = hotValue.peek() + (hotTarget - hotValue.peek()) * k;
});

export function cursorFxPointerMove(event: PointerMoveEvent): void {
  if (mode === "none") return;
  raw.value = [event.position.x, event.position.y];
  hotTarget = event.target.kind === "none" ? 0 : 1;
  const layer = event.target.kind === "layer" ? COMPOSITOR.layer.current[event.target.layerId]?.layer : undefined;
  overPanel = layer === "top" || layer === "overlay";
  applyTheme();
}

// The effect draws under Top/Overlay layers, so the system pointer returns over them.
function applyTheme(): void {
  const theme = mode === "none" || overPanel ? VISIBLE_THEME : HIDDEN_THEME;
  if (theme === cursorTheme) return;
  cursorTheme = theme;
  COMPOSITOR.cursor.configure({ theme, size: 24 });
}

function sync(): void {
  modeValue.value = MODES.indexOf(mode);
  applyTheme();
  if (mode === "none") animation.stop(CLOCK);
  else {
    last = Date.now();
    animation.start(CLOCK, { from: 0, to: 1, duration: 1000, repeat: "loop" });
  }
  for (const [output, handle] of active) {
    if (mode === "none" || !COMPOSITOR.output.list.includes(output)) {
      active.delete(output);
      handle.dispose();
    }
  }
  if (mode === "none") return;
  for (const name of COMPOSITOR.output.list) if (!active.has(name)) void enable(name);
}

async function enable(name: string): Promise<void> {
  const output = COMPOSITOR.output.current[name];
  if (!output?.resolution || output.scale <= 0) return;
  try {
    const handle = await COMPOSITOR.effect.overlay(name, {
      persistent: true,
      // The single top slot belongs to night colour and screen shaders; panels show the system pointer.
      placement: "below-layers",
      effect: compileOverlayEffect({
        input: backdropSource(), alpha: "preserve",
        invalidate: { kind: "always" },
        pipeline: [shaderStage(SHADER, { uniforms: {
          cursor_mode: modeValue, cursor_pos: SMOOTH, cursor_raw: RAW, cursor_hot: hotValue,
          cursor_origin: [output.position.x, output.position.y],
          cursor_extent: [output.resolution.width / output.scale, output.resolution.height / output.scale],
        } })],
      }),
    });
    if (mode === "none" || active.has(name)) { handle.dispose(); return; }
    active.set(name, handle);
    error = "";
    void handle.closed.then(() => { if (active.get(name) === handle) active.delete(name); });
  } catch (failure) {
    error = String(failure);
    console.error("Cursor effect overlay failed:", name, failure);
  }
}

// Output changes dispose overlays natively: rebuild them for the new layout.
export function refreshCursorFx(): void {
  active.clear();
  sync();
}

export function stopCursorFx(): void {
  mode = "none";
  sync();
}

export function registerCursorFxIpc(ipc: IpcServer): void {
  const state = () => ({ mode, modes: MODES, overlays: [...active.keys()], error });
  ipc.handle("cursor-fx.get", state);
  ipc.handle("cursor-fx.set", params => {
    const next = (params as { mode?: unknown } | undefined)?.mode;
    if (!MODES.includes(next as Mode)) throw new TypeError("Unknown cursor effect");
    mode = next as Mode;
    sync();
    ipc.broadcast("cursor-fx.changed", state());
    return state();
  });
}
