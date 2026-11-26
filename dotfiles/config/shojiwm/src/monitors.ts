import { COMPOSITOR, type DisplayConfigDraft } from "shoji_wm";
import type { IpcServer } from "shoji_wm/ipc";

type Entry = { name: string; x: number; y: number; scale: number;
  width: number; height: number; refreshRate: number };
type Mode = { mode: "disabled" } | { mode: "mirror"; source: string };
type Settings = { primary: string; outputs: Entry[]; modes: Record<string, Mode> };

function cleanModes(value: unknown): Record<string, Mode> {
  const result: Record<string, Mode> = {};
  if (!value || typeof value !== "object") return result;
  for (const [name, item] of Object.entries(value as Record<string, any>)) {
    if (item?.mode === "disabled") result[name] = { mode: "disabled" };
    else if (item?.mode === "mirror" && typeof item.source === "string" && item.source !== name)
      result[name] = { mode: "mirror", source: item.source };
  }
  return result;
}

export function registerMonitors(server: IpcServer) {
  let saved: Settings = { primary: COMPOSITOR.env.get("SHOJI_PRIMARY_OUTPUT") || "", outputs: [], modes: {} };
  let preview: Settings | null = null;
  let deadline = 0;
  let timer: ReturnType<typeof setTimeout> | undefined;
  const state = () => ({ primary: COMPOSITOR.output.list.includes(saved.primary) ? saved.primary : COMPOSITOR.output.list[0] || "", settings: saved, deadline,
    modes: saved.modes,
    disabled: Object.values(COMPOSITOR.output.current).filter(o => !o.enabled).map(o => o.name),
    outputs: COMPOSITOR.output.outputs.filter(o => o.enabled && o.resolution).map(o => ({
      name: o.name, description: o.description || o.model || o.name,
      x: o.position.x, y: o.position.y, scale: o.scale,
      ...o.resolution!, modes: o.availableModes,
    })) });
  const notify = () => server.broadcast("monitors.changed", state());
  function validate(value: unknown, restoring = false): Settings {
    const data = value as Settings;
    if (!data || typeof data.primary !== "string" || !Array.isArray(data.outputs))
      throw new Error("Некорректные настройки мониторов");
    const outputs = data.outputs;
    const names = new Set<string>();
    const supported: Entry[] = [];
    for (const item of outputs) {
      if (!item || typeof item.name !== "string") throw new Error("Некорректный монитор");
      const output = COMPOSITOR.output.get(item.name);
      if ((!restoring && !output?.enabled) || names.has(item.name)) throw new Error("Список мониторов изменился. Обнови настройки.");
      names.add(item.name);
      if (![item.x, item.y, item.scale, item.width, item.height, item.refreshRate].every(Number.isFinite)
          || !Number.isInteger(item.x) || !Number.isInteger(item.y)
          || Math.abs(item.x) > 32768 || Math.abs(item.y) > 32768
          || item.scale < 0.5 || item.scale > 3
          || item.width <= 0 || item.height <= 0 || item.refreshRate <= 0)
        throw new Error("Монитор не поддерживает выбранные параметры");
      if (output?.enabled && !output.availableModes.some(m => m.width === item.width && m.height === item.height
          && Math.abs(m.refreshRate - item.refreshRate) < 0.01)) {
        // A different display can occupy a saved connector. Restore the other
        // entries and let this output use the automatic best-mode fallback.
        if (restoring) continue;
        throw new Error("Монитор не поддерживает выбранные параметры");
      }
      supported.push({ ...item });
    }
    if (!restoring && (names.size !== COMPOSITOR.output.list.length || !names.has(data.primary)))
      throw new Error("Выбери главный экран и настрой все подключённые мониторы");
    return { primary: data.primary, outputs: supported, modes: restoring ? cleanModes((data as Partial<Settings>).modes) : saved.modes };
  }
  COMPOSITOR.output.configure(context => {
    const draft: DisplayConfigDraft = {};
    for (const output of context.connected) {
      const item = (preview || saved).outputs.find(o => o.name === output.name);
      const mode = saved.modes[output.name];
      const source = mode?.mode === "mirror" ? mode.source : "";
      // A stale mirror (source gone, disabled or itself mirrored) falls back to extend.
      const usable = source && source !== output.name && context.connected.some(o => o.name === source)
        && saved.modes[source]?.mode !== "disabled" && saved.modes[source]?.mode !== "mirror";
      if (mode?.mode === "disabled") draft[output.name] = { mode: "disabled" };
      else if (usable) draft[output.name] = { mode: "mirror", source };
      else draft[output.name] = item ? { mode: "extend", position: { x: item.x, y: item.y }, scale: item.scale,
        transform: output.transform,
        resolution: { width: item.width, height: item.height, refreshRate: item.refreshRate } }
        : { mode: "extend", resolution: "best", position: "auto", scale: 1 };
    }
    // Never leave the desktop without a screen (e.g. the external display was
    // unplugged while the laptop panel was disabled): wake the disabled ones.
    // The saved mode is kept, so replugging restores the earlier setup.
    if (context.connected.length && context.connected.every(o => draft[o.name]?.mode === "disabled"))
      for (const output of context.connected) {
        const item = saved.outputs.find(o => o.name === output.name);
        draft[output.name] = item ? { mode: "extend", position: { x: item.x, y: item.y }, scale: item.scale,
          transform: output.transform, resolution: { width: item.width, height: item.height, refreshRate: item.refreshRate } }
          : { mode: "extend", resolution: "best", position: "auto", scale: 1 };
      }
    return draft;
  });
  function cancel() {
    if (timer) clearTimeout(timer);
    timer = undefined;
    preview = null;
    deadline = 0;
    COMPOSITOR.output.reconfigure();
    notify();
    return state();
  }
  server.handle("monitors.get", state);
  server.handle("monitors.restore", params => {
    if (preview) throw new Error("Сначала заверши проверку настроек");
    saved = validate(params, true);
    COMPOSITOR.output.reconfigure();
    notify();
    return state();
  });
  server.handle("monitors.apply-layout", params => {
    if (preview) throw new Error("Сначала заверши проверку настроек");
    const next = validate(params);
    for (const item of next.outputs) {
      const actual = COMPOSITOR.output.get(item.name);
      if (!actual?.resolution || actual.resolution.width !== item.width
          || actual.resolution.height !== item.height
          || Math.abs(actual.scale - item.scale) > 0.01
          || Math.abs(actual.resolution.refreshRate - item.refreshRate) > 0.01)
        throw new Error("Частота или масштаб изменились. Обнови настройки и примени их с проверкой.");
    }
    const previous = saved;
    saved = { ...saved, primary: next.primary, outputs: [
      ...saved.outputs.filter(o => !COMPOSITOR.output.list.includes(o.name)), ...next.outputs,
    ] };
    try { COMPOSITOR.output.reconfigure(); }
    catch (error) { saved = previous; COMPOSITOR.output.reconfigure(); throw error; }
    notify();
    return state();
  });
  server.handle("monitors.preview", params => {
    if (preview) throw new Error("Сначала заверши проверку настроек");
    const next = validate(params);
    // Capture the actual layout, including outputs not present in the saved file.
    saved = { ...saved, primary: saved.primary || COMPOSITOR.output.list[0] || "", outputs: [
      ...saved.outputs.filter(o => !COMPOSITOR.output.list.includes(o.name)),
      ...state().outputs.map(o => ({ ...o })),
    ] };
    preview = next;
    deadline = Date.now() + 15000;
    timer = setTimeout(cancel, 15000);
    try { COMPOSITOR.output.reconfigure(); } catch (error) { cancel(); throw error; }
    notify();
    return state();
  });
  server.handle("monitors.confirm", () => {
    if (!preview) throw new Error("Время проверки истекло");
    validate(preview);
    // A compositor may translate the entire desktop to a different origin.
    // Verify the relative arrangement instead of rejecting that translation.
    const first = preview.outputs[0];
    const origin = COMPOSITOR.output.get(first.name)?.position;
    const offsetX = origin ? origin.x - first.x : 0;
    const offsetY = origin ? origin.y - first.y : 0;
    for (const item of preview.outputs) {
      const actual = COMPOSITOR.output.get(item.name);
      if (!actual?.resolution || Math.abs(actual.scale - item.scale) > 0.01
          || actual.resolution.width !== item.width || actual.resolution.height !== item.height
          || Math.abs(actual.resolution.refreshRate - item.refreshRate) > 0.1
          || actual.position.x - item.x !== offsetX || actual.position.y - item.y !== offsetY)
        throw new Error("Система не применила выбранные параметры. Верни прежние настройки.");
    }
    saved = { ...saved, primary: preview.primary, outputs: [
      ...saved.outputs.filter(o => !COMPOSITOR.output.list.includes(o.name)),
      ...preview.outputs.map(o => ({ ...o, x: o.x + offsetX, y: o.y + offsetY })),
    ] };
    preview = null;
    deadline = 0;
    if (timer) clearTimeout(timer);
    timer = undefined;
    notify();
    return state();
  });
  server.handle("monitors.mode", params => {
    if (preview) throw new Error("Сначала заверши проверку настроек");
    const { name, mode, source } = (params || {}) as { name?: string; mode?: string; source?: string };
    const live = COMPOSITOR.output.list;
    const modes = { ...saved.modes };
    const active = (n: string) => live.includes(n) && !modes[n];
    if (typeof name !== "string") throw new Error("Некорректный монитор");
    if (mode === "extend") {
      if (!live.includes(name) && !Object.values(COMPOSITOR.output.current).some(o => o.name === name))
        throw new Error("Список мониторов изменился. Обнови настройки.");
      delete modes[name];
    } else if (mode === "disabled") {
      if (!live.includes(name)) throw new Error("Список мониторов изменился. Обнови настройки.");
      // Mirrors of this screen fall back to extend, so drop them before the guard.
      for (const [n, m] of Object.entries(modes)) if (m.mode === "mirror" && m.source === name) delete modes[n];
      // Never turn off the last real screen: the desktop would be unreachable.
      if (!live.some(n => n !== name && active(n))) throw new Error("Нельзя выключить последний экран");
      modes[name] = { mode: "disabled" };
    } else if (mode === "mirror") {
      if (typeof source !== "string" || source === name || !live.includes(name) || !active(source))
        throw new Error("Для зеркала нужен другой включённый экран");
      if (Object.values(modes).some(m => m.mode === "mirror" && m.source === name))
        throw new Error("Этот экран уже показывают на других. Сначала убери их зеркала.");
      modes[name] = { mode: "mirror", source };
    } else throw new Error("Некорректный режим монитора");
    const previous = saved;
    saved = { ...saved, modes };
    try { COMPOSITOR.output.reconfigure(); }
    catch (error) { saved = previous; COMPOSITOR.output.reconfigure(); throw error; }
    notify();
    return state();
  });
  server.handle("monitors.cancel", cancel);
  COMPOSITOR.onDisable(event => {
    if (preview) cancel();
    if (event.isReloading) event.persist("monitor-settings", saved);
  });
  COMPOSITOR.onEnable(event => {
    if (!event.isReloading) return;
    const previous = event.restore<Settings>("monitor-settings");
    if (previous) { saved = validate(previous, true); COMPOSITOR.output.reconfigure(); }
  });
}
