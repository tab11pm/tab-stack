#!/usr/bin/env python3
"""Preview or apply two narrowly scoped session hooks, with guarded rollback."""
import argparse
import os
from pathlib import Path
import sys

from session_install import apply_files, rollback, safe_path

ROOT = Path(__file__).resolve().parents[1]
TS_OLD = '  command: ["bash", `${scripts}/session-portals`],'
TS_NEW = '  command: COMPOSITOR.env.get("TAB_STACK_SESSION_TOKEN")\n    ? ["python3", `${scripts}/session_lifecycle.py`, "ready"]\n    : ["bash", `${scripts}/session-portals`],'
QML_REPLACEMENTS = (
    ('    readonly property string sessionId: Quickshell.env("XDG_SESSION_ID")\n', ''),
    ('        if (name === "logout" && !sessionId) { error = "Не удалось определить сессию"; return; }\n', ''),
    ('        if (pending === "logout" && sessionId) action.command = ["loginctl", "terminate-session", sessionId];',
     '        if (pending === "logout") action.command = ["python3", decodeURIComponent(Qt.resolvedUrl("../shojiwm/scripts/logout").toString().replace("file://", ""))];'),
    ('        onExited: exitCode => { if (exitCode !== 0) root.error = "Система не разрешила действие"; }',
     '        stderr: SplitParser { onRead: data => { root.error = data.trim(); } }\n        onExited: exitCode => { if (exitCode !== 0 && !root.error) root.error = "Система не разрешила действие"; }'),
)


def replace_once(text: str, old: str, new: str) -> str:
    if text.count(old) != 1:
        raise ValueError('Unknown or duplicated integration hook; no files changed')
    return text.replace(old, new, 1)


def patch_index(text: str) -> str:
    if text.count(TS_NEW) == 1 and text.count(TS_OLD) == 0:
        return text
    return replace_once(text, TS_OLD, TS_NEW)


def patch_qml(text: str) -> str:
    old_logout, new_logout = QML_REPLACEMENTS[2]
    if text.count(new_logout) == 1 and old_logout not in text:
        if 'sessionId' in text or text.count(QML_REPLACEMENTS[3][1]) != 1:
            raise ValueError('Incomplete native logout migration')
        return text
    for old, new in QML_REPLACEMENTS:
        text = replace_once(text, old, new)
    return text


def render_desktop_entry(executable: Path) -> str:
    path = str(executable)
    if not executable.is_absolute() or any(char in path for char in '=\n\r\0'):
        raise ValueError('Desktop executable must be absolute and contain no = or line breaks')
    # SDDM 0.21 sends raw Exec as one argument to a script ending in exec $@.
    # Use only fixed words: no quote parsing, variable substitution or private paths.
    command = '/usr/bin/python3 -P -m tab_stack_session start'
    return (ROOT / 'system/session/tab-stack.desktop.in').read_text().replace('@TAB_STACK_SESSION_EXEC@', command)



def preview(home: Path, config: Path | None = None, state: Path | None = None):
    config = config or home / '.config'
    state = state or home / '.local/state'
    changes = {}
    for path, patcher in ((config / 'shojiwm/src/index.tsx', patch_index), (config / 'shoji-shell/HomeSystemCard.qml', patch_qml)):
        safe_path(path)
        if not path.is_file(): raise ValueError(f'Missing integration file: {path.name}')
        changes[path] = (patcher(path.read_text()).encode(), path.stat().st_mode & 0o777)
    entry = state / 'tab-stack/session/tab-stack.desktop'; safe_path(entry)
    rendered = render_desktop_entry(home / '.local/bin/tab-stack-session').encode()
    if entry.exists() and entry.read_bytes() != rendered:
        raise ValueError('Unreviewed existing rendered desktop entry')
    changes[entry] = (rendered, 0o600)
    return changes


def apply(home: Path, config: Path | None = None, state: Path | None = None) -> Path:
    changes = preview(home, config, state)
    return apply_files(changes, (state or home / '.local/state') / 'tab-stack/backups')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group()
    group.add_argument('--apply', action='store_true')
    group.add_argument('--rollback', type=Path, metavar='MANIFEST')
    parser.add_argument('--target-home', type=Path)
    args = parser.parse_args()
    home = args.target_home.absolute() if args.target_home else Path.home()
    config = home / '.config' if args.target_home else Path(os.environ.get('XDG_CONFIG_HOME', str(home / '.config')))
    state = home / '.local/state' if args.target_home else Path(os.environ.get('XDG_STATE_HOME', str(home / '.local/state')))
    try:
        if (args.apply or args.rollback) and os.geteuid() == 0:
            raise ValueError("Run as your desktop user, not root or sudo")
        if args.rollback:
            rollback(args.rollback.absolute()); print('Guarded rollback completed; no services changed.')
        elif args.apply:
            print(f'Migration manifest: {apply(home, config, state)}')
        else:
            for path in preview(home, config, state): print(path)
            print('Preview only; no files or services changed.')
        return 0
    except (ValueError, OSError) as exc:
        print(f'Migration refused: {exc}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
