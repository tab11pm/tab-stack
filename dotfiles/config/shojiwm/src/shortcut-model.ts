export interface ShortcutOverrideFile {
  version: 1;
  overrides: Record<string, string | null>;
  custom: Array<{ id: string; title: string; shortcut: string; command: string }>;
}

export interface ShortcutDefinition {
  id: string;
  title: string;
  category: string;
  shortcut: string;
  handler: () => void;
}

export interface ResolvedShortcut extends ShortcutDefinition {
  defaultShortcut: string;
  kind: "system" | "custom";
  enabled: boolean;
  command?: string;
}

export const EMPTY_SHORTCUTS: ShortcutOverrideFile = { version: 1, overrides: {}, custom: [] };
export const PROTECTED_SHORTCUTS = new Set(["Super+K", "Super+Shift+K", "Super+Shift+R", "Super+Shift+Q"]);

export function isMissingShortcutFile(error: unknown): boolean {
  if (!error || typeof error !== "object") return false;
  const value = error as { name?: unknown; code?: unknown };
  return value.name === "NotFound" || value.code === "ENOENT";
}

const keys = new Set([
  "Space", "Return", "Tab", "Escape", "BackSpace", "Delete", "Insert",
  "Home", "End", "PageUp", "PageDown", "Left", "Right", "Up", "Down",
  "Print", "XF86AudioMute", "XF86AudioRaiseVolume", "XF86AudioLowerVolume",
]);

export function normalizeShortcut(value: string): string | null {
  if (typeof value !== "string" || value.length > 80) return null;
  const parts = value.split("+").map(part => part.trim()).filter(Boolean);
  if (parts.length < 1 || parts.length > 5) return null;
  const modifierNames: Record<string, string> = {
    win: "Super", meta: "Super", super: "Super", ctrl: "Ctrl", control: "Ctrl",
    alt: "Alt", shift: "Shift",
  };
  const modifiers = new Set<string>();
  for (const part of parts.slice(0, -1)) {
    const modifier = modifierNames[part.toLowerCase()];
    if (!modifier || modifiers.has(modifier)) return null;
    modifiers.add(modifier);
  }
  const key = parts.at(-1)!;
  const canonical = key.length === 1 ? key.toUpperCase() : key;
  if (!/^[A-Z0-9]$/.test(canonical) && !/^F(?:[1-9]|1[0-9]|2[0-4])$/.test(canonical) && !keys.has(canonical)) return null;
  if (parts.length === 1 && !canonical.startsWith("XF86")) return null;
  return [...["Super", "Ctrl", "Alt", "Shift"].filter(modifier => modifiers.has(modifier)), canonical].join("+");
}

export function parseShortcutSettings(raw: unknown): ShortcutOverrideFile {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return EMPTY_SHORTCUTS;
  const value = raw as Record<string, unknown>;
  if (value.version !== 1) return EMPTY_SHORTCUTS;
  const overrides: Record<string, string | null> = {};
  if (value.overrides && typeof value.overrides === "object" && !Array.isArray(value.overrides)) {
    for (const [id, shortcut] of Object.entries(value.overrides)) {
      if (!/^[a-z0-9-]{1,80}$/.test(id)) continue;
      if (shortcut === null) overrides[id] = null;
      else if (typeof shortcut === "string" && normalizeShortcut(shortcut)) overrides[id] = normalizeShortcut(shortcut)!;
    }
  }
  const custom: ShortcutOverrideFile["custom"] = [];
  const entries = Array.isArray(value.custom) ? value.custom.slice(0, 100) : [];
  const ids = new Set<string>();
  for (const item of entries) {
    if (!item || typeof item !== "object") continue;
    const entry = item as Record<string, unknown>;
    if (typeof entry.id !== "string" || !/^user-[a-zA-Z0-9_-]{1,64}$/.test(entry.id) || ids.has(entry.id)) continue;
    if (typeof entry.title !== "string" || !entry.title.trim() || entry.title.length > 80) continue;
    if (typeof entry.command !== "string" || !entry.command.trim() || entry.command.length > 2048) continue;
    const shortcut = typeof entry.shortcut === "string" ? normalizeShortcut(entry.shortcut) : null;
    if (!shortcut) continue;
    ids.add(entry.id);
    custom.push({ id: entry.id, title: entry.title.trim(), shortcut, command: entry.command.trim() });
  }
  return { version: 1, overrides, custom };
}

export function resolveShortcuts(defaults: ShortcutDefinition[], settings: ShortcutOverrideFile): { rows: ResolvedShortcut[]; warnings: string[] } {
  const rows: ResolvedShortcut[] = [];
  const warnings: string[] = [];
  const used = new Set(PROTECTED_SHORTCUTS);
  const registered = new Map<string, string | null>();

  // Existing default keys win over remaps so a malformed file cannot hide a core action.
  for (const item of defaults) {
    const override = ["shortcuts", "shortcut-manager", "window-switcher-next", "window-switcher-previous"].includes(item.id) ? undefined : settings.overrides[item.id];
    if (override === undefined) {
      const shortcut = normalizeShortcut(item.shortcut);
      registered.set(item.id, shortcut);
      if (shortcut) used.add(shortcut);
    }
  }
  for (const item of defaults) {
    if (registered.has(item.id)) continue;
    const override = settings.overrides[item.id];
    if (override === null) { registered.set(item.id, null); continue; }
    const shortcut = typeof override === "string" ? normalizeShortcut(override) : null;
    if (!shortcut || used.has(shortcut)) {
      warnings.push(`Invalid or conflicting shortcut for ${item.id}`);
      const fallback = normalizeShortcut(item.shortcut);
      registered.set(item.id, fallback && !used.has(fallback) ? fallback : null);
      if (fallback && !used.has(fallback)) used.add(fallback);
    } else {
      registered.set(item.id, shortcut);
      used.add(shortcut);
    }
  }
  for (const item of defaults) {
    const shortcut = registered.get(item.id) ?? "";
    rows.push({ ...item, shortcut, defaultShortcut: item.shortcut, kind: "system", enabled: shortcut !== "" });
  }
  for (const item of settings.custom) {
    if (used.has(item.shortcut)) {
      warnings.push(`Conflicting custom shortcut ${item.id}`);
      continue;
    }
    used.add(item.shortcut);
    rows.push({ id: item.id, title: item.title, category: "СВОИ КОМАНДЫ", shortcut: item.shortcut,
      defaultShortcut: "", kind: "custom", enabled: true, command: item.command, handler: () => {} });
  }
  return { rows, warnings };
}
