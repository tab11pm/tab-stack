#!/usr/bin/env bash
# Adds the cursor effect to the live config without touching anything else.
set -euo pipefail
src="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../config" && pwd)"
dst="${XDG_CONFIG_HOME:-$HOME/.config}"
cp "$src"/shojiwm/src/effect/cursor-fx.{ts,frag} "$dst/shojiwm/src/effect/"
cp "$src"/shoji-shell/CursorFx{,Settings}.qml "$dst/shoji-shell/"
data="${XDG_DATA_HOME:-$HOME/.local/share}/icons"
mkdir -p "$data" && cp -r "$src"/../data/icons/shoji-hidden-cursor "$data/"
python3 -I - "$dst" <<'PY'
import sys
L = sys.argv[1]
def rep(path, anchor, new, marker):
    p = f"{L}/{path}"; s = open(p).read()
    if marker in s: print("already", path); return
    if s.count(anchor) != 1: sys.exit(f"anchor not found once in {path}: {anchor!r}")
    open(p + ".bak-cursorfx", "w").write(s)
    open(p, "w").write(s.replace(anchor, new)); print("patched", path)
rep("shoji-shell/qmldir", "IdleSleepSettings 1.0 IdleSleepSettings.qml\n",
    "IdleSleepSettings 1.0 IdleSleepSettings.qml\nsingleton CursorFx 1.0 CursorFx.qml\nCursorFxSettings 1.0 CursorFxSettings.qml\n", "CursorFx")
rep("shoji-shell/shell.qml", "    readonly property bool activityReady",
    "    readonly property bool cursorFxReady: CursorFx.loaded\n    readonly property bool activityReady", "CursorFx")
rep("shoji-shell/ControlCentre.qml", "    IdleSleepSettings { Layout.fillWidth: true }\n",
    "    IdleSleepSettings { Layout.fillWidth: true }\n    CursorFxSettings { Layout.fillWidth: true }\n", "CursorFxSettings")
t = "shojiwm/src/index.tsx"
rep(t, "import { registerScreenShaderIpc,", 'import { cursorFxPointerMove, refreshCursorFx, registerCursorFxIpc } from "./effect/cursor-fx";\nimport { registerScreenShaderIpc,', "registerCursorFxIpc }")
rep(t, "const WORKSPACE_IPC = createIpcServer();\n", "const WORKSPACE_IPC = createIpcServer();\nregisterCursorFxIpc(WORKSPACE_IPC);\n", "registerCursorFxIpc(")
rep(t, "  HYBRID_WINDOW_MANAGER.onPointerMove(event);\n", "  HYBRID_WINDOW_MANAGER.onPointerMove(event);\n  cursorFxPointerMove(event);\n", "cursorFxPointerMove(")
rep(t, "  stopRetroScreen();\n  HYBRID_WINDOW_MANAGER.onOutputChange(event);", "  stopRetroScreen();\n  refreshCursorFx();\n  HYBRID_WINDOW_MANAGER.onOutputChange(event);", "refreshCursorFx(")
PY
echo "Done. Reload ShojiWM (Super+Shift+R) and restart the shell. Backups: *.bak-cursorfx"
