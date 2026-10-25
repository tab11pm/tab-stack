import { isMissingShortcutFile, normalizeShortcut, parseShortcutSettings, resolveShortcuts, type ShortcutDefinition } from "../config/shojiwm/src/shortcut-model.ts";

const defaults: ShortcutDefinition[] = [
  { id: "shortcuts", title: "Menu", category: "System", shortcut: "Super+K", handler: () => {} },
  { id: "shortcut-manager", title: "Manager", category: "System", shortcut: "Super+Shift+K", handler: () => {} },
  { id: "terminal", title: "Terminal", category: "System", shortcut: "Super+Return", handler: () => {} },
  { id: "launcher", title: "Launcher", category: "System", shortcut: "Super+Space", handler: () => {} },
];

Deno.test("normalizes supported key names and rejects incomplete shortcuts", () => {
  if (normalizeShortcut("Win + Shift + u") !== "Super+Shift+U") throw new Error("alias normalization failed");
  if (normalizeShortcut("XF86AudioMute") !== "XF86AudioMute") throw new Error("media key rejected");
  if (normalizeShortcut("Win +") !== null) throw new Error("incomplete shortcut accepted");
});

Deno.test("system overrides, disabled actions and custom commands resolve together", () => {
  const settings = parseShortcutSettings({ version: 1,
    overrides: { shortcuts: null, "shortcut-manager": null, terminal: "Win+Shift+T", launcher: null },
    custom: [{ id: "user-demo", title: "Demo", shortcut: "Win+U", command: "echo demo" }],
  });
  const result = resolveShortcuts(defaults, settings);
  if (result.rows.find(row => row.id === "shortcuts")?.shortcut !== "Super+K") throw new Error("list was disabled");
  if (result.rows.find(row => row.id === "shortcut-manager")?.shortcut !== "Super+Shift+K") throw new Error("manager was disabled");
  if (result.rows.find(row => row.id === "terminal")?.shortcut !== "Super+Shift+T") throw new Error("override failed");
  if (result.rows.find(row => row.id === "launcher")?.enabled !== false) throw new Error("disable failed");
  if (result.rows.find(row => row.id === "user-demo")?.command !== "echo demo") throw new Error("custom command missing");
});

Deno.test("conflicting custom shortcut is skipped", () => {
  const settings = parseShortcutSettings({ version: 1, overrides: {},
    custom: [{ id: "user-conflict", title: "Conflict", shortcut: "Super+Return", command: "echo conflict" }],
  });
  const result = resolveShortcuts(defaults, settings);
  if (result.rows.some(row => row.id === "user-conflict")) throw new Error("conflict was registered");
  if (!result.warnings.length) throw new Error("conflict warning missing");
});

Deno.test("missing shortcut settings file is recognized without Deno.errors", () => {
  const missing = Object.assign(new Error("No such file"), { name: "NotFound" });
  if (!isMissingShortcutFile(missing)) throw new Error("missing file was not recognized");
  if (isMissingShortcutFile(new TypeError("readTextFileSync is not a function"))) throw new Error("runtime error was hidden");
});
