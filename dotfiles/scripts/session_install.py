"""Small guarded file transactions shared by session install and migration."""
import hashlib
import json
import os
from pathlib import Path
import stat
import subprocess
import tempfile


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def safe_path(path: Path) -> None:
    if not path.is_absolute() or any(c in str(path) for c in '\n\r\0'):
        raise ValueError('Target must be an absolute single-line path')
    for item in (path, *path.parents):
        if item.is_symlink():
            raise ValueError(f'Symlink target refused: {item.name}')
        if item.exists():
            info = item.stat()
            if item == path:
                if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid():
                    raise ValueError(f'Unowned or non-regular target: {item.name}')
            elif not stat.S_ISDIR(info.st_mode):
                raise ValueError('Non-directory ancestor')


def atomic_write(path: Path, data: bytes, mode: int) -> None:
    safe_path(path)
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    fd, temporary = tempfile.mkstemp(prefix='.tab-stack-', dir=path.parent)
    try:
        with os.fdopen(fd, 'wb') as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
            os.fchmod(stream.fileno(), mode)
        os.replace(temporary, path)
    finally:
        Path(temporary).unlink(missing_ok=True)


def snapshot(path: Path) -> dict:
    safe_path(path)
    if not path.exists():
        return {'target': str(path), 'present': False}
    info = path.stat()
    return {'target': str(path), 'present': True, 'mode': stat.S_IMODE(info.st_mode),
            'uid': info.st_uid, 'gid': info.st_gid, 'sha256': digest(path.read_bytes())}


def unchanged(entry: dict) -> bool:
    path = Path(entry['target'])
    now = snapshot(path)
    return all(now.get(key) == entry.get(key) for key in ('present', 'mode', 'uid', 'gid', 'sha256'))


def apply_files(changes: dict[Path, tuple[bytes, int]], state_root: Path) -> Path:
    originals = [snapshot(path) for path in changes]
    # All paths checked before any target or backup write.
    for ancestor in (state_root, *state_root.parents):
        if ancestor.is_symlink(): raise ValueError('Unsafe backup ancestor')
    state_root.mkdir(parents=True, exist_ok=True, mode=0o700)
    backup = Path(tempfile.mkdtemp(prefix='session-', dir=state_root))
    manifest = backup / 'manifest.json'
    entries = []
    for index, (path, (data, mode)) in enumerate(changes.items()):
        entry = {**originals[index], 'installed_sha256': digest(data), 'installed_mode': mode, 'installed_uid': os.getuid()}
        if entry['present']:
            previous = backup / f'{index}.previous'
            atomic_write(previous, path.read_bytes(), 0o600)
            if digest(previous.read_bytes()) != entry['sha256']:
                raise ValueError('Target changed during backup')
            entry['backup'] = str(previous)
        entries.append(entry)
    value = {'version': 1, 'entries': entries, 'status': 'prepared'}
    atomic_write(manifest, (json.dumps(value, indent=2)+'\n').encode(), 0o600)
    if not all(unchanged(entry) for entry in entries):
        raise ValueError('Target changed after preview')
    written = []
    try:
        for entry, (path, (data, mode)) in zip(entries, changes.items()):
            if not unchanged(entry): raise ValueError('Target changed before write')
            atomic_write(path, data, mode)
            entry['installed_gid'] = path.stat().st_gid
            written.append(entry)
        value['status'] = 'installed'
        atomic_write(manifest, (json.dumps(value, indent=2)+'\n').encode(), 0o600)
    except Exception:
        conflicts = []
        for entry in reversed(written):
            try:
                if not installed_matches(entry):
                    raise ValueError('Written target changed during rollback')
                restore(entry)
            except (ValueError, OSError):
                conflicts.append(entry['target'])
        value['status'] = 'recovery-required' if conflicts else 'rolled-back'
        value['conflicts'] = conflicts
        atomic_write(manifest, (json.dumps(value, indent=2)+'\n').encode(), 0o600)
        raise

    return manifest


def installed_matches(entry: dict) -> bool:
    path = Path(entry['target'])
    try:
        safe_path(path)
        info = path.stat()
        return (digest(path.read_bytes()) == entry['installed_sha256']
                and stat.S_IMODE(info.st_mode) == entry['installed_mode']
                and info.st_uid == entry['installed_uid']
                and info.st_gid == entry['installed_gid'])
    except (ValueError, OSError):
        return False


def restore(entry: dict) -> None:
    path = Path(entry['target'])
    safe_path(path)
    if entry['present']:
        previous = Path(entry['backup'])
        atomic_write(path, previous.read_bytes(), entry['mode'])
        if path.stat().st_gid != entry['gid']:
            os.chown(path, -1, entry['gid'])
    else:
        path.unlink(missing_ok=True)


def rollback(manifest: Path) -> None:
    safe_path(manifest)
    info = manifest.stat()
    if stat.S_IMODE(info.st_mode) != 0o600 or stat.S_IMODE(manifest.parent.stat().st_mode) != 0o700:
        raise ValueError('Rollback requires private manifest and backup')
    value = json.loads(manifest.read_text())
    if value.get('version') != 1 or value.get('status') != 'installed':
        raise ValueError('Manifest is not an installed transaction')
    entries = value['entries']
    for entry in entries:
        path = Path(entry['target']); safe_path(path)
        if not installed_matches(entry):
            raise ValueError(f'Installed file changed; rollback refused: {path.name}')
        if entry['present']:
            previous = Path(entry['backup']); safe_path(previous)
            if previous.parent != manifest.parent or stat.S_IMODE(previous.stat().st_mode) != 0o600 or digest(previous.read_bytes()) != entry['sha256'] or entry['uid'] != os.getuid():
                raise ValueError('Backup identity or checksum mismatch')
    # Preflight every record before restoring any target.
    for entry in reversed(entries):
        if not installed_matches(entry):
            value['status'] = 'recovery-required'
            value['conflicts'] = [entry['target']]
            atomic_write(manifest, (json.dumps(value, indent=2)+'\n').encode(), 0o600)
            raise ValueError('Target changed after rollback preflight; preserved')
        restore(entry)
    value['status'] = 'rolled-back'
    atomic_write(manifest, (json.dumps(value, indent=2)+'\n').encode(), 0o600)


def session_changes(root: Path, home: Path, config: Path, reviewed: dict[str, str] | None = None) -> dict[Path, tuple[bytes, int]]:
    # Query the exact interpreter used by SDDM; respect an explicit user base.
    environment = dict(os.environ)
    if home != Path.home():
        environment['PYTHONUSERBASE'] = str(home / '.local')
    user_site = Path(subprocess.run(
        ['/usr/bin/python3', '-P', '-c', 'import site; print(site.getusersitepackages())'],
        env=environment, capture_output=True, text=True, check=True).stdout.strip())
    paths = [
        (root / 'config/shojiwm/scripts/session_state.py', config / 'shojiwm/scripts/session_state.py'),
        (root / 'config/shojiwm/scripts/session_lifecycle.py', config / 'shojiwm/scripts/session_lifecycle.py'),
        (root / 'bin/tab-stack-session', home / '.local/bin/tab-stack-session'),
        (root / 'bin/tab-stack-session', user_site / 'tab_stack_session.py'),
    ]
    for source in sorted((root / 'config/systemd/user').rglob('*')):
        if source.is_file(): paths.append((source, config / 'systemd/user' / source.relative_to(root / 'config/systemd/user')))
    result = {}
    for source, target in paths:
        safe_path(target)
        data = source.read_bytes()
        if target.exists() and target.read_bytes() != data and (reviewed or {}).get(str(target)) != digest(target.read_bytes()):
            raise ValueError(f'Existing session file needs reviewed checksum: {target}')
        result[target] = (data, 0o755 if target.name == 'tab-stack-session' else 0o644)
    return result
