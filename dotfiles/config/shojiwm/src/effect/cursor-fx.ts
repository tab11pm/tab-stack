import {
  COMPOSITOR, animationVariable, createAnimationController, signal, effect,
  shaderStage, loadShader, type PointerMoveEvent, type ShaderUniformVec2,
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
let mode: Mode = "none";
let hotTarget = 0;
let last = Date.now();
// A transparent theme hides the system pointer while the shader draws it.
const HIDDEN_THEME = "shoji-hidden-cursor";
const envTheme = COMPOSITOR.env.get("XCURSOR_THEME");
// shortcut: a reload while hidden falls back to Adwaita, store the theme if a custom one matters.
const VISIBLE_THEME = envTheme && envTheme !== HIDDEN_THEME ? envTheme : "Adwaita";
let cursorTheme = "";
let pointerOutput: string | undefined;
let lastRetry = 0;
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

// The top slot holds one overlay per output, so retro-screen.ts draws this stage in its overlay.
let host = { sync: () => {}, rebuild: () => {}, drawn: (_output?: string) => false };
export function bindCursorFxHost(next: typeof host): void { host = next; }
export function cursorFxOn(): boolean { return mode !== "none"; }

export function cursorFxStage(name: string) {
  const output = COMPOSITOR.output.current[name];
  if (!output?.resolution || output.scale <= 0) throw new Error("Cursor effect output disappeared");
  return shaderStage(SHADER, { uniforms: {
    cursor_mode: modeValue, cursor_pos: SMOOTH, cursor_raw: RAW, cursor_hot: hotValue,
    cursor_origin: [output.position.x, output.position.y],
    cursor_extent: [output.resolution.width / output.scale, output.resolution.height / output.scale],
  } });
}

export function cursorFxPointerMove(event: PointerMoveEvent): void {
  if (mode === "none") return;
  raw.value = [event.position.x, event.position.y];
  hotTarget = event.target.kind === "none" ? 0 : 1;
  pointerOutput = event.outputName;
  // The compositor closes overlays while the session is locked: rebuild them once it is back.
  if (!host.drawn(pointerOutput) && Date.now() - lastRetry > 1000) {
    lastRetry = Date.now();
    host.sync();
  }
  applyTheme();
}

// The system pointer returns wherever no overlay draws the effect (lock screen, failed or closed overlay).
export function cursorFxOverlayChanged(): void { applyTheme(); }
function applyTheme(): void {
  const theme = mode !== "none" && host.drawn(pointerOutput) ? HIDDEN_THEME : VISIBLE_THEME;
  if (theme === cursorTheme) return;
  cursorTheme = theme;
  COMPOSITOR.cursor.configure({ theme, size: 24 });
  // configure() also exports the theme: apps started now (the lock screen too) must keep a visible one.
  COMPOSITOR.env.apply({ XCURSOR_THEME: VISIBLE_THEME });
  COMPOSITOR.env.publish(["XCURSOR_THEME"]);
}

function sync(): void {
  modeValue.value = MODES.indexOf(mode);
  if (mode === "none") animation.stop(CLOCK);
  else {
    last = Date.now();
    animation.start(CLOCK, { from: 0, to: 1, duration: 1000, repeat: "loop" });
  }
  host.sync();
  applyTheme();
}

// Output changes move origins and extents: rebuild the overlays for the new layout.
export function refreshCursorFx(): void {
  if (mode !== "none") host.rebuild();
}

export function stopCursorFx(): void {
  mode = "none";
  sync();
}

export function registerCursorFxIpc(ipc: IpcServer): void {
  const state = () => ({ mode, modes: MODES });
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
