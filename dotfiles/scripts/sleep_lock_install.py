"""Scoped opt-in files. Never invoke systemctl, logind, QML or authentication."""
from pathlib import Path
from session_install import digest, safe_path, session_changes


def sleep_changes(root: Path, home: Path, config: Path, reviewed: dict[str, str]):
    # Require a matching installed independent session; do not silently upgrade its other units.
    core = session_changes(root, home, config, reviewed)
    lifecycle = config / 'shojiwm/scripts/session_lifecycle.py'
    for target, (data, mode) in core.items():
        if not target.is_file():
            raise ValueError('Install the independent session component before sleep-lock')
        if target != lifecycle and target.read_bytes() != data:
            raise ValueError('Base session needs a separate reviewed update')
    shell = config / 'shoji-shell'
    for name in ('lock/launch.py', 'lock/SessionLock.qml', 'lock/pam/shoji-lock', 'lock.qml', 'lock-check.qml'):
        path = shell / name
        safe_path(path)
        if not path.is_file():
            raise ValueError('Install the independent locker before sleep-lock')
        if name not in ('lock/launch.py', 'lock/SessionLock.qml') and path.read_bytes() != (root/'config/shoji-shell'/name).read_bytes():
            raise ValueError('Locker support file needs separate review')
    pairs = [
        (root/'config/shojiwm/scripts'/name, config/'shojiwm/scripts'/name)
        for name in ('session_lifecycle.py', 'sleep_lock.py', 'sleep_lock_runtime.py')
    ]
    pairs += [(root/'config/shoji-shell'/name, shell/name) for name in ('lock/launch.py', 'lock/SessionLock.qml')]
    pairs += [(root/'optional/sleep-lock/tab-stack-sleep-lock.service',config/'systemd/user/tab-stack-sleep-lock.service'),
              (root/'optional/sleep-lock/sleep-lock.conf',config/'systemd/user/tab-stack-session.target.d/sleep-lock.conf')]
    changes = {}
    for source, target in pairs:
        safe_path(target)
        data = source.read_bytes()
        if target.exists() and target.read_bytes() != data and reviewed.get(str(target)) != digest(target.read_bytes()):
            raise ValueError(f'Existing sleep lock file needs reviewed checksum: {target}')
        changes[target] = data, 0o644
    return changes
