import {
  COMPOSITOR, backdropSource, compileOverlayEffect, loadShader, shaderStage, signal,
  type OverlayHandle, type WaylandLayer,
} from "shoji_wm";
import type { IpcServer } from "shoji_wm/ipc";
import { aquariumOverlayEffect, setAquariumEnabled } from "./aquarium";
import { nightColorStage, nightColorState, setNightColor } from "./night-color";

const SHADER = loadShader("./src/effect/retro-screen.frag");
const active = new Map<string, { id: string; handle?: OverlayHandle }>();
const enabled = signal(0);
const items = [
  { id: "none", title: "Без эффекта", description: "Обычный рабочий стол",
    details: "Исходное изображение без постобработки" },
  { id: "retro", title: "CRT Pixel", description: "Пиксели · полосы · выпуклый экран",
    details: "768 строк, исходные цвета, мягкое свечение и лёгкая выпуклость CRT" },
  { id: "aquarium", title: "Аквариум", description: "Толща воды · стекло · объёмные пузырьки",
    details: "Оптика стеклянного резервуара, расфокус по глубине и объёмное освещение" },
];
let selected = "none";
let preview: string | null = null;
let previewSession: string | null = null;
const pickerSessions = new Map<string, string | null>();
let error = "";
let nightError = "";
// Preserve user intent when native lock cleanup removes the applied overlay.
let nightRequested = false;
let notify = () => {};

function currentId(): string { return preview ?? selected; }
function wanted(): boolean { return currentId() !== "none" || nightColorState().enabled; }
function state() { return { items, selected, preview: currentId(), active: currentId(), previewing: preview !== null, error }; }

function sync(): void {
  const id = currentId();
  enabled.value = id === "retro" ? 1 : 0;
  setAquariumEnabled(id === "aquarium");
  // Pending openings finish before the next shader can occupy the same slot.
  for (const [output, entry] of active) {
    if ((!wanted() || entry.id !== id || !COMPOSITOR.output.list.includes(output)) && entry.handle) {
      active.delete(output);
      entry.handle.dispose();
    }
  }
  if (!wanted()) return;
  for (const output of COMPOSITOR.output.list) {
    if (active.has(output)) continue;
    void enableScreenShader(output, id).catch(failure => {
      error = "Не удалось показать эффект: " + String(failure);
      if (nightColorState().enabled) {
        nightError = "Не удалось применить ночной фильтр: " + String(failure);
        setNightColor(false, nightColorState().temperature);
        sync();
      }
      console.error("Screen shader overlay failed:", output, failure);
      notify();
      notifyNight();
    });
  }
}

async function enableScreenShader(output: string, id: string): Promise<void> {
  const entry: { id: string; handle?: OverlayHandle } = { id };
  active.set(output, entry);
  try {
    const handle = await COMPOSITOR.effect.overlay(output, {
      persistent: true,
      placement: "top",
      effect: id === "aquarium" ? aquariumOverlayEffect(output) : compileOverlayEffect({
        input: backdropSource(),
        alpha: "preserve",
        pipeline: id === "retro"
          ? [shaderStage(SHADER, { uniforms: { rows: 768, enabled } }), nightColorStage()]
          : [nightColorStage()],
      }),
    });
    if (active.get(output) !== entry || !wanted() || currentId() !== id || !COMPOSITOR.output.list.includes(output)) {
      if (active.get(output) === entry) active.delete(output);
      handle.dispose();
      sync();
      return;
    }
    entry.handle = handle;
    void handle.closed.then(() => {
      if (active.get(output) !== entry) return;
      active.delete(output);
      // Another top overlay or native cleanup ended this effect; do not fight it.
      if (wanted()) {
        // A replaced top overlay must not repeatedly steal the same slot.
        if (nightColorState().enabled) {
          setNightColor(false, nightColorState().temperature);
          nightError = "Ночной фильтр прерван другим экранным эффектом";
          notifyNight();
        }
        stopRetroScreen();
      }
    });
  } catch (error) {
    if (active.get(output) === entry) {
      active.delete(output);
      if (currentId() === id) throw error;
      sync();
    }
  }
}

export function stopRetroScreen(): void {
  selected = "none";
  preview = null;
  previewSession = null;
  sync();
  notify();
}

let notifyNight = () => {};
export function stopScreenEffects(): void {
  nightRequested = false;
  setNightColor(false, nightColorState().temperature);
  stopRetroScreen();
}

export function cancelScreenShaderPreview(): void {
  if (preview === null) return;
  preview = null;
  previewSession = null;
  error = "";
  sync();
  notify();
}

export function screenShaderPickerMapped(layer: WaylandLayer): void {
  if (layer.namespace() === "shoji-shader-picker") pickerSessions.set(layer.id, previewSession);
}

export function screenShaderPickerClosed(layer: WaylandLayer): void {
  if (layer.namespace() !== "shoji-shader-picker") return;
  const session = pickerSessions.get(layer.id);
  pickerSessions.delete(layer.id);
  // A delayed destroy from the previous opening must not cancel the new preview.
  if (session && session === previewSession) cancelScreenShaderPreview();
}

export function registerScreenShaderIpc(ipc: IpcServer,
  previewScene: (output: string) => { origin: number[]; extent: number[]; windows: number[][] } | null): void {
  notify = () => ipc.broadcast("screen-shaders.changed", state());
  const nightState = () => ({ ...nightColorState(), error: nightError });
  notifyNight = () => ipc.broadcast("night-light.changed", nightState());
  ipc.handle("night-light.get", nightState);
  ipc.handle("night-light.set", params => {
    const request = params as { enabled?: unknown; temperature?: unknown } | undefined;
    if (typeof request?.enabled !== "boolean" || typeof request.temperature !== "number"
      || !Number.isFinite(request.temperature) || request.temperature < 2500 || request.temperature > 6500)
      throw new TypeError("Invalid night-light settings");
    nightError = "";
    nightRequested = request.enabled;
    setNightColor(request.enabled, request.temperature);
    sync();
    notifyNight();
    return nightState();
  });
  // Display-only notification from the locker after authenticated unlock.
  // Never fight native cleanup immediately or revive CRT/aquarium effects.
  ipc.handle("night-light.resume", () => {
    if (nightRequested && !nightColorState().enabled) {
      nightError = "";
      setNightColor(true, nightColorState().temperature);
      sync();
      notifyNight();
    }
    return nightState();
  });
  ipc.handle("screen-shaders.get", params => {
    const output = (params as { output?: unknown } | undefined)?.output;
    return { ...state(), scene: typeof output === "string" ? previewScene(output) : null };
  });
  ipc.handle("screen-shaders.preview", params => {
    const request = params as { id?: string; session?: string } | undefined;
    const id = request?.id;
    if (!items.some(item => item.id === id)) throw new TypeError("Unknown screen shader");
    if (typeof request?.session !== "string" || !request.session) throw new TypeError("Missing picker session");
    previewSession = request.session;
    for (const layer of Object.values(COMPOSITOR.layer.current)) {
      if (layer.namespace === "shoji-shader-picker" && !pickerSessions.get(layer.id))
        pickerSessions.set(layer.id, previewSession);
    }
    preview = id!;
    error = "";
    sync();
    notify();
    return state();
  });
  ipc.handle("screen-shaders.apply", () => {
    selected = preview ?? selected;
    preview = null;
    previewSession = null;
    sync();
    notify();
    return state();
  });
  ipc.handle("screen-shaders.cancel", () => { cancelScreenShaderPreview(); return state(); });
}
