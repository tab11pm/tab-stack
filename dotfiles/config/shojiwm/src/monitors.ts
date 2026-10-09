import { COMPOSITOR, type DisplayConfigDraft } from "shoji_wm";
import type { IpcServer } from "shoji_wm/ipc";

type Entry = { name: string; x: number; y: number; scale: number;
  width: number; height: number; refreshRate: number };
type Settings = { primary: string; outputs: Entry[] };

export function registerMonitors(server: IpcServer) {
  let saved: Settings = { primary: COMPOSITOR.env.get("SHOJI_PRIMARY_OUTPUT") || "", outputs: [] };
  let preview: Settings | null = null;
  let deadline = 0;
  let timer: ReturnType<typeof setTimeout> | undefined;
  const state = () => ({ primary: COMPOSITOR.output.list.includes(saved.primary) ? saved.primary : COMPOSITOR.output.list[0] || "", settings: saved, deadline,
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
    for (const item of outputs) {
      if (!item || typeof item.name !== "string") throw new Error("Некорректный монитор");
      const output = COMPOSITOR.output.get(item.name);
      if ((!restoring && !output?.enabled) || names.has(item.name)) throw new Error("Список мониторов изменился. Обнови настройки.");
      names.add(item.name);
      if (![item.x, item.y, item.scale, item.width, item.height, item.refreshRate].every(Number.isFinite)
          || !Number.isInteger(item.x) || !Number.isInteger(item.y)
          || Math.abs(item.x) > 32768 || Math.abs(item.y) > 32768
          || item.scale < 0.5 || item.scale > 3
          || item.width <= 0 || item.height <= 0 || item.refreshRate <= 0
          || (output && !output.availableModes.some(m => m.width === item.width && m.height === item.height
            && Math.abs(m.refreshRate - item.refreshRate) < 0.01)))
        throw new Error("Монитор не поддерживает выбранные параметры");
    }
    if (!restoring && (names.size !== COMPOSITOR.output.list.length || !names.has(data.primary)))
      throw new Error("Выбери главный экран и настрой все подключённые мониторы");
    return { primary: data.primary, outputs: outputs.map(o => ({ ...o })) };
  }
  COMPOSITOR.output.configure(context => {
    const draft: DisplayConfigDraft = {};
    for (const output of context.connected) {
      const item = (preview || saved).outputs.find(o => o.name === output.name);
      draft[output.name] = item ? { mode: "extend", position: { x: item.x, y: item.y }, scale: item.scale,
        transform: output.transform,
        resolution: { width: item.width, height: item.height, refreshRate: item.refreshRate } }
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
    saved = { primary: next.primary, outputs: [
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
    saved = { primary: saved.primary || COMPOSITOR.output.list[0] || "", outputs: [
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
    saved = { primary: preview.primary, outputs: [
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
