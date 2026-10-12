"""Private session ownership; no account settings or general environment dumps."""
from dataclasses import asdict, dataclass
import json
import os
from pathlib import Path
import socket
import stat
import struct
import tempfile
from typing import Mapping

PROC_ROOT = Path('/proc')
ENVIRONMENT_KEYS = ('WAYLAND_DISPLAY', 'DISPLAY', 'XDG_CURRENT_DESKTOP', 'XDG_SESSION_TYPE', 'QT_QPA_PLATFORM')


@dataclass(frozen=True)
class OwnerIdentity:
    pid: int
    uid: int
    start_ticks: int
    boot_id: str
    token: str
    session_id: str


@dataclass(frozen=True)
class SessionRecord:
    owner: OwnerIdentity
    compositor: OwnerIdentity | None
    phase: str
    services: tuple[str, ...]


def private_path(path: Path, directory: bool = False) -> None:
    info = path.lstat()
    expected = stat.S_ISDIR if directory else stat.S_ISREG
    if not expected(info.st_mode) or info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) != (0o700 if directory else 0o600):
        raise ValueError(f'Unsafe session metadata: {path.name}')


def prepare_runtime(runtime: Path) -> None:
    runtime.mkdir(mode=0o700, exist_ok=True)
    private_path(runtime, True)


def read_private_json(path: Path) -> dict:
    private_path(path.parent, True)
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    except OSError as exc:
        raise ValueError('Cannot open private session metadata') from exc
    with os.fdopen(fd) as stream:
        info = os.fstat(stream.fileno())
        if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) != 0o600:
            raise ValueError('Unsafe session file')
        try:
            result = json.load(stream)
        except (ValueError, TypeError) as exc:
            raise ValueError('Malformed session metadata') from exc
    if not isinstance(result, dict):
        raise ValueError('Malformed session metadata')
    return result


def write_private_json(path: Path, value: dict) -> None:
    private_path(path.parent, True)
    if path.exists() or path.is_symlink():
        private_path(path)
    fd, temporary = tempfile.mkstemp(prefix='.session-', dir=path.parent)
    try:
        with os.fdopen(fd, 'w') as stream:
            json.dump(value, stream)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        Path(temporary).unlink(missing_ok=True)


def parse_identity(value: dict) -> OwnerIdentity:
    try:
        result = OwnerIdentity(**value)
        if any(type(getattr(result, key)) is not int for key in ('pid', 'uid', 'start_ticks')):
            raise ValueError('Invalid identity numbers')
        if result.pid <= 0 or result.uid < 0 or result.start_ticks < 0:
            raise ValueError('Invalid identity numbers')
        if any(not isinstance(getattr(result, key), str) or not getattr(result, key) for key in ('boot_id', 'token', 'session_id')):
            raise ValueError('Invalid identity fields')
        return result
    except (TypeError, KeyError) as exc:
        raise ValueError('Malformed session identity') from exc


def load_session(runtime: Path) -> SessionRecord:
    value = read_private_json(runtime / 'owner.json')
    try:
        if value['phase'] not in ('starting', 'ready', 'stopping', 'failed-cleanup'):
            raise ValueError('Invalid session phase')
        if not isinstance(value['services'], list) or any(not isinstance(unit, str) for unit in value['services']):
            raise ValueError('Invalid services')
        return SessionRecord(parse_identity(value['owner']), parse_identity(value['compositor']) if value['compositor'] is not None else None, value['phase'], tuple(value['services']))
    except (KeyError, TypeError) as exc:
        raise ValueError('Malformed session record') from exc


def load_owner(runtime: Path) -> OwnerIdentity:
    return load_session(runtime).owner


def save_session(runtime: Path, record: SessionRecord) -> None:
    write_private_json(runtime / 'owner.json', asdict(record))


def process_identity(pid: int, token: str, session_id: str, proc_root: Path = PROC_ROOT) -> OwnerIdentity:
    process = proc_root / str(pid)
    fields = (process / 'stat').read_text().rsplit(')', 1)[1].split()
    return OwnerIdentity(pid, process.stat().st_uid, int(fields[19]), (proc_root / 'sys/kernel/random/boot_id').read_text().strip(), token, session_id)


def owner_is_current(owner: OwnerIdentity, proc_root: Path = PROC_ROOT) -> bool:
    try:
        return process_identity(owner.pid, owner.token, owner.session_id, proc_root) == owner
    except (OSError, ValueError, IndexError):
        return False


def selected_environment(env: Mapping[str, str]) -> dict[str, str]:
    if not env.get('WAYLAND_DISPLAY') or env.get('XDG_CURRENT_DESKTOP') != 'ShojiWM' or env.get('XDG_SESSION_TYPE') != 'wayland':
        raise ValueError('Expected a live ShojiWM Wayland environment')
    selected = {key: env.get(key, '') for key in ENVIRONMENT_KEYS}
    if any('\x00' in value or '\n' in value for value in selected.values()):
        raise ValueError('Invalid desktop environment value')
    return selected


def conflicting_sessions(records: list[dict[str, str]], uid: int, current_session_id: str) -> list[str]:
    return [record['Id'] for record in records if record.get('User') == str(uid) and record.get('Id') != current_session_id and record.get('Type') in ('wayland', 'x11') and record.get('Class') in ('user', 'user-early', 'user-light')]


def verify_wayland_peer(display: str, runtime: Path, uid: int, compositor: OwnerIdentity) -> None:
    path = Path(display) if Path(display).is_absolute() else runtime / display
    try:
        info = path.lstat()
        if not stat.S_ISSOCK(info.st_mode) or info.st_uid != uid:
            raise ValueError('Wayland socket owner mismatch')
        with socket.socket(socket.AF_UNIX) as client:
            client.settimeout(2)
            client.connect(str(path))
            pid, peer_uid, _ = struct.unpack('3i', client.getsockopt(socket.SOL_SOCKET, socket.SO_PEERCRED, struct.calcsize('3i')))
        if pid != compositor.pid or peer_uid != uid or compositor.uid != uid or not owner_is_current(compositor, PROC_ROOT):
            raise ValueError('Wayland peer identity mismatch')
        if (PROC_ROOT / str(pid) / 'exe').resolve().name != 'shoji_wm':
            raise ValueError('Wayland peer is not ShojiWM')
    except OSError as exc:
        raise ValueError('Cannot verify Wayland peer') from exc
