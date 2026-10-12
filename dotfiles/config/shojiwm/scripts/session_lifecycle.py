#!/usr/bin/env python3
"""Own one ShojiWM process and a narrowly scoped user-service lease."""
from contextlib import contextmanager
from dataclasses import asdict, replace
import fcntl
import hashlib
import stat
import os
from pathlib import Path
import secrets
import signal
import subprocess
import sys
import time
from typing import Mapping, Protocol

from session_state import (ENVIRONMENT_KEYS, OwnerIdentity, SessionRecord, conflicting_sessions,
                           load_session, prepare_runtime, private_path, process_identity,
                           read_private_json, save_session, selected_environment,
                           verify_wayland_peer, write_private_json, parse_identity)

SESSION_UNITS = ('elephant.service', 'xdg-desktop-portal.service', 'xdg-desktop-portal-gtk.service',
                 'xdg-desktop-portal-wlr.service', 'xdg-desktop-portal-shojiwm.service')
SESSION_TARGET = 'tab-stack-session.target'
READINESS_SECONDS = 90
CLEANUP_SECONDS = 30
COMMAND_SECONDS = 10

# Digests of reviewed user units shipped alongside this runtime.
OWNED_FILE_DIGESTS = {'tab-stack-session.target': '8812ec0af17544530964645be75b2f3f2ba087970b2b435aabbf84c6d8f90638', 'elephant.service': '705bce2c29fb522e7e9cad4a46f7432351d30374097cadd17457f0033aa5e674', 'xdg-desktop-portal.service.d/tab-stack-session.conf': 'ca0a19621666949da53abef999f00feac566cc821db3ab8f326c8f83679fb7ab', 'xdg-desktop-portal-gtk.service.d/tab-stack-session.conf': 'ca0a19621666949da53abef999f00feac566cc821db3ab8f326c8f83679fb7ab', 'xdg-desktop-portal-wlr.service.d/tab-stack-session.conf': 'ca0a19621666949da53abef999f00feac566cc821db3ab8f326c8f83679fb7ab', 'xdg-desktop-portal-shojiwm.service.d/tab-stack-session.conf': 'ca0a19621666949da53abef999f00feac566cc821db3ab8f326c8f83679fb7ab'}


class SessionBackend(Protocol):
    runtime: Path
    def sessions(self) -> list[dict[str, str]]: ...
    def identity(self, pid: int) -> OwnerIdentity: ...
    def unit_states(self, names: tuple[str, ...]) -> dict[str, str]: ...
    def selected_manager_environment(self) -> dict[str, str]: ...
    def command(self, argv: list[str], env: Mapping[str, str] | None, timeout: float) -> subprocess.CompletedProcess[str]: ...
    def spawn(self, argv: list[str], env: Mapping[str, str]) -> subprocess.Popen: ...
    def validate_units(self) -> None: ...
    def descendant(self, pid: int, ancestor: int) -> bool: ...
    def verify_peer(self, env: Mapping[str, str], compositor: OwnerIdentity) -> None: ...
    def owns_unreaped_child(self, child: subprocess.Popen) -> bool: ...


class SystemBackend:
    def __init__(self, env: Mapping[str, str]):
        root = Path(env.get('XDG_RUNTIME_DIR', ''))
        if not root.is_absolute() or root.is_symlink() or root.stat().st_uid != os.getuid():
            raise ValueError('Invalid XDG_RUNTIME_DIR')
        self.runtime = root / 'tab-stack-session'
        self.environment = dict(env)
        self.deadline = None
        self.children = {}

    def command(self, argv, env=None, timeout=COMMAND_SECONDS):
        if self.deadline is not None:
            timeout = min(timeout, self.deadline - time.monotonic())
        if timeout <= 0:
            raise ValueError('Session operation deadline expired')
        result = subprocess.run(argv, env=dict(env) if env is not None else None, capture_output=True,
                                text=True, timeout=timeout, check=False)
        if result.returncode:
            # Deliberately do not print arbitrary subprocess output or environment.
            raise ValueError(f'Session command failed: {argv[0]} {argv[2] if len(argv) > 2 else ""}')
        return result

    def sessions(self):
        ids = self.command(['loginctl', 'list-sessions', '--no-legend', '--no-pager'], None, COMMAND_SECONDS).stdout
        records = []
        for line in ids.splitlines():
            sid = line.split()[0]
            data = self.command(['loginctl', 'show-session', sid, '--no-pager',
                                 '-p', 'User', '-p', 'Type', '-p', 'Class', '-p', 'State', '-p', 'Leader'], None, COMMAND_SECONDS).stdout
            record = dict(item.split('=', 1) for item in data.splitlines() if '=' in item)
            record['Id'] = sid
            records.append(record)
        return records

    def identity(self, pid):
        return process_identity(pid, 'unassigned', self.environment.get('XDG_SESSION_ID', 'unknown'))

    def unit_states(self, names):
        result = {}
        for name in names:
            output = self.command(['systemctl', '--user', 'show', name, '-p', 'ActiveState', '--value'], None, COMMAND_SECONDS).stdout.strip()
            if output not in ('active', 'inactive', 'failed', 'activating', 'deactivating', 'reloading'):
                raise ValueError(f'Unknown unit state: {name}')
            result[name] = output
        return result

    def selected_manager_environment(self):
        # systemctl exposes no selective show-environment operation. Filter immediately;
        # never log or persist its full stdout.
        result = self.command(['systemctl', '--user', 'show-environment'], None, COMMAND_SECONDS)
        selected = {}
        for line in result.stdout.splitlines():
            key, sep, value = line.partition('=')
            if sep and key in ENVIRONMENT_KEYS:
                # systemctl emits dollar-single-quoted C escapes for shell metacharacters.
                # shlex alone keeps the leading dollar, corrupting e.g. wayland;xcb.
                # Decode only a string literal; never execute shell assignments.
                if value.startswith("$'"):
                    import ast
                    try:
                        decoded = ast.literal_eval(value[1:])
                    except (ValueError, SyntaxError) as exc:
                        raise ValueError('Malformed selected manager value') from exc
                    if not isinstance(decoded, str):
                        raise ValueError('Malformed selected manager value')
                    selected[key] = decoded
                    continue
                import shlex
                parsed = shlex.split(line)
                if len(parsed) != 1:
                    raise ValueError('Malformed selected manager value')
                selected[key] = parsed[0].split('=', 1)[1]
        return selected

    def validate_units(self):
        def checked_file(path, name):
            info = path.lstat()
            if (not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid()
                    or stat.S_IMODE(info.st_mode) != 0o644
                    or hashlib.sha256(path.read_bytes()).hexdigest() != OWNED_FILE_DIGESTS[name]):
                raise ValueError(f'Unreviewed session file: {name}')
        expected = Path(self.environment.get('XDG_CONFIG_HOME', str(Path.home() / '.config'))) / 'systemd/user'
        for name in (*SESSION_UNITS, SESSION_TARGET):
            data = self.command(['systemctl', '--user', 'show', name, '-p', 'LoadState', '-p', 'FragmentPath', '-p', 'DropInPaths', '-p', 'PartOf', '-p', 'NeedDaemonReload'], None, COMMAND_SECONDS).stdout
            values = dict(line.split('=', 1) for line in data.splitlines() if '=' in line)
            if values.get('NeedDaemonReload') != 'no':
                raise ValueError(f'Session unit requires daemon-reload: {name}')
            if values.get('LoadState') != 'loaded':
                raise ValueError(f'Missing session unit: {name}')
            if name in ('elephant.service', SESSION_TARGET):
                path = expected / name
                if values.get('FragmentPath') != str(path) or values.get('DropInPaths', ''):
                    raise ValueError(f'Unexpected session unit provenance: {name}')
                checked_file(path, name)
            else:
                fragment = Path(values.get('FragmentPath', ''))
                dropin = expected / (name + '.d') / 'tab-stack-session.conf'
                if fragment != Path('/usr/lib/systemd/user') / name or values.get('DropInPaths', '').split() != [str(dropin)]:
                    raise ValueError(f'Unexpected portal provenance: {name}')
                checked_file(dropin, name + '.d/tab-stack-session.conf')
            if name != SESSION_TARGET and SESSION_TARGET not in values.get('PartOf', '').split():
                raise ValueError(f'Missing session stop ownership: {name}')

    def descendant(self, pid, ancestor):
        seen = set()
        while pid > 0 and pid not in seen:
            if pid == ancestor:
                return True
            seen.add(pid)
            try:
                fields = (Path('/proc') / str(pid) / 'stat').read_text().rsplit(')', 1)[1].split()
                pid = int(fields[1])
            except (OSError, ValueError, IndexError):
                return False
        return False

    def verify_peer(self, env, compositor):
        verify_wayland_peer(env['WAYLAND_DISPLAY'], Path(self.environment['XDG_RUNTIME_DIR']), os.getuid(), compositor)

    def spawn(self, argv, env):
        child = subprocess.Popen(argv, env=dict(env))
        self.children[child.pid] = child
        return child

    def owns_unreaped_child(self, child):
        if self.children.get(child.pid) is not child or child.returncode is not None:
            return False
        try:
            # WNOWAIT checks our direct child without freeing its PID for reuse.
            return os.waitid(os.P_PID, child.pid, os.WEXITED | os.WNOHANG | os.WNOWAIT) is None
        except (OSError, ChildProcessError):
            return False


def same_process(a: OwnerIdentity, b: OwnerIdentity) -> bool:
    return (a.pid, a.uid, a.start_ticks, a.boot_id) == (b.pid, b.uid, b.start_ticks, b.boot_id)


def current(backend: SessionBackend, owner: OwnerIdentity) -> bool:
    try:
        return same_process(backend.identity(owner.pid), owner)
    except (OSError, ValueError, IndexError):
        return False


def completed_logins(backend: SessionBackend) -> list[tuple[OwnerIdentity, OwnerIdentity]]:
    path = backend.runtime / 'completed.json'
    if not path.exists() and not path.is_symlink():
        return []
    value = read_private_json(path)
    if set(value) != {'sessions'} or not isinstance(value['sessions'], list):
        raise ValueError('Invalid completed session receipts')
    result = []
    for item in value['sessions']:
        if not isinstance(item, dict) or set(item) != {'owner', 'compositor'}:
            raise ValueError('Invalid completed session receipt')
        owner, compositor = parse_identity(item['owner']), parse_identity(item['compositor'])
        if (owner.uid != os.getuid() or compositor.uid != owner.uid
                or compositor.boot_id != owner.boot_id or compositor.token != owner.token
                or compositor.session_id != owner.session_id):
            raise ValueError('Completed session identity mismatch')
        result.append((owner, compositor))
    return result


def validate_login(backend: SessionBackend, session_id: str, pid: int) -> None:
    records = backend.sessions()
    incoming = [item for item in records if item.get('Id') == session_id]
    if len(incoming) != 1 or incoming[0].get('User') != str(os.getuid()) or incoming[0].get('Type') != 'wayland' or incoming[0].get('Class') not in ('user', 'user-early', 'user-light'):
        raise ValueError('Incoming Wayland login is not verified')
    try:
        leader = int(incoming[0]['Leader'])
    except (KeyError, ValueError) as exc:
        raise ValueError('Invalid logind leader') from exc
    if not backend.descendant(pid, leader):
        raise ValueError('Wrapper does not belong to incoming login')
    conflicts = conflicting_sessions(records, os.getuid(), session_id)
    if conflicts:
        receipts = completed_logins(backend)
        boot_id = backend.identity(pid).boot_id
        for sid in conflicts:
            old = next(item for item in records if item['Id'] == sid)
            verified_closed = old.get('State') == 'closing' and any(
                owner.session_id == sid and owner.boot_id == boot_id
                and not current(backend, owner) and not current(backend, compositor)
                for owner, compositor in receipts)
            if not verified_closed:
                raise ValueError('Another graphical session uses this UID; no services changed')


@contextmanager
def private_lock(runtime: Path, name: str, deadline: float | None = None):
    path = runtime / name
    if path.exists() or path.is_symlink():
        private_path(path)
    fd = os.open(path, os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW, 0o600)
    try:
        private_path(path)
        while True:
            try:
                fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except BlockingIOError as exc:
                if deadline is None or time.monotonic() >= deadline:
                    raise ValueError('Session operation is already owned') from exc
                time.sleep(min(0.05, max(0, deadline - time.monotonic())))
        yield
    finally:
        os.close(fd)


def run(backend, argv, deadline, env=None):
    remaining = deadline - time.monotonic()
    if remaining <= 0:
        raise ValueError('Session operation deadline expired')
    result = backend.command(argv, env, min(COMMAND_SECONDS, remaining))
    if result.returncode:
        raise ValueError(f'Session command failed: {argv[0]}')
    return result


@contextmanager
def budget(backend, deadline):
    previous = getattr(backend, 'deadline', None)
    backend.deadline = deadline
    try:
        yield
    finally:
        backend.deadline = previous


def readiness_record(backend, env):
    record = load_session(backend.runtime)
    if env.get('TAB_STACK_SESSION_TOKEN') != record.owner.token or not current(backend, record.owner):
        raise ValueError('Unknown or stale wrapper owner')
    if record.compositor is None or not current(backend, record.compositor):
        raise ValueError('Unknown or stale compositor')
    if not backend.descendant(os.getpid(), record.compositor.pid):
        raise ValueError('Readiness caller is not a compositor descendant')
    validate_login(backend, record.owner.session_id, record.owner.pid)
    selected = selected_environment(env)
    backend.verify_peer(selected, record.compositor)
    return record, selected


def ready_session(backend: SessionBackend, env: Mapping[str, str]) -> None:
    deadline = time.monotonic() + READINESS_SECONDS
    with budget(backend, deadline), private_lock(backend.runtime, 'operation.lock', deadline):
        # Child identity is written just after spawn; the child can reach us first.
        while True:
            record = load_session(backend.runtime)
            if record.compositor is not None:
                break
            if record.phase != 'starting' or time.monotonic() >= deadline:
                raise ValueError('Compositor identity not ready')
            time.sleep(0.02)
        record, selected = readiness_record(backend, env)
        if record.phase == 'ready':
            if any(value != 'active' for value in backend.unit_states(SESSION_UNITS).values()):
                raise ValueError('Ready session service failed')
            return
        if record.phase != 'starting' or record.services != SESSION_UNITS:
            raise ValueError('Session is not awaiting readiness')
        backend.validate_units()
        # Record selected values BEFORE any import: partial import remains recoverable.
        before = backend.selected_manager_environment()
        write_private_json(backend.runtime / 'ready.json', {'token': record.owner.token, 'environment': selected, 'manager_before': before, 'ready': False})
        run(backend, ['dbus-update-activation-environment', '--systemd', *[f'{key}={value}' for key, value in selected.items()]], deadline)
        if backend.selected_manager_environment() != selected:
            raise ValueError('Systemd did not receive the selected desktop environment')
        activated = tuple(unit for unit, status in backend.unit_states(SESSION_UNITS).items() if status != 'inactive')
        run(backend, ['systemctl', '--user', 'start', SESSION_TARGET], deadline)
        if activated:
            run(backend, ['systemctl', '--user', 'restart', *activated], deadline)
        states = backend.unit_states((*SESSION_UNITS, SESSION_TARGET))
        if any(states.get(name) != 'active' for name in (*SESSION_UNITS, SESSION_TARGET)):
            raise ValueError('Session services did not become active')
        # Revalidate the lease after slow service jobs, before declaring readiness.
        live, _ = readiness_record(backend, env)
        if live.phase != 'starting':
            raise ValueError('Readiness lease is no longer starting')
        write_private_json(backend.runtime / 'ready.json', {'token': record.owner.token, 'environment': selected, 'manager_before': before, 'ready': True})
        save_session(backend.runtime, replace(record, phase='ready'))


def cleanup_session(backend: SessionBackend, owner: OwnerIdentity) -> None:
    deadline = min(time.monotonic() + CLEANUP_SECONDS, getattr(backend, 'deadline', None) or float('inf'))
    try:
        with budget(backend, deadline), private_lock(backend.runtime, 'operation.lock', deadline):
            record = load_session(backend.runtime)
            if record.owner != owner or not current(backend, owner):
                raise ValueError('Cleanup ownership mismatch')
            validate_login(backend, owner.session_id, owner.pid)
            save_session(backend.runtime, replace(record, phase='stopping'))
            if record.services:
                if record.services != SESSION_UNITS:
                    raise ValueError('Unexpected service lease')
                backend.validate_units()
                # Explicit services cover pre-target D-Bus activation too.
                run(backend, ['systemctl', '--user', 'stop', SESSION_TARGET, *record.services], deadline)
                stopped = backend.unit_states((*record.services, SESSION_TARGET))
                if any(value not in ('inactive', 'failed') for value in stopped.values()):
                    raise ValueError('Owned services remain running')
                failed = tuple(name for name, value in stopped.items() if value == 'failed')
                if failed:
                    # A portal can exit on the disappearing display before stop reaches it.
                    # Preserve its journal diagnosis; normalize only our stopped lease.
                    print('Stopped owned units retained failure status: ' + ', '.join(failed), file=sys.stderr)
                    run(backend, ['systemctl', '--user', 'reset-failed', *failed], deadline)
                    if any(value != 'inactive' for value in backend.unit_states((*record.services, SESSION_TARGET)).values()):
                        raise ValueError('Owned services did not settle inactive')
            ready_path = backend.runtime / 'ready.json'
            if ready_path.exists() or ready_path.is_symlink():
                values = read_private_json(ready_path)
                if values.get('token') != owner.token or not isinstance(values.get('environment'), dict):
                    raise ValueError('Environment lease mismatch')
                selected = selected_environment(values['environment'])
                manager = backend.selected_manager_environment()
                before = values.get('manager_before')
                if not isinstance(before, dict) or any(key not in ENVIRONMENT_KEYS for key in before):
                    raise ValueError('Missing independent D-Bus environment lease')
                # D-Bus can succeed even when systemd import fails. Invalidate keys
                # unchanged from pre-import OR still matching our selected values.
                # A changed foreign manager value is preserved in both managers.
                dbus_owned = [key for key in ENVIRONMENT_KEYS
                              if manager.get(key) == selected[key] or manager.get(key) == before.get(key)]
                owned = [key for key in ENVIRONMENT_KEYS if key in manager and manager[key] == selected[key]]
                if dbus_owned:
                    run(backend, ['dbus-update-activation-environment', *[f'{key}=' for key in dbus_owned]], deadline)
                before_unset = backend.selected_manager_environment()
                owned = [key for key in owned if before_unset.get(key) == selected[key]]
                if owned:
                    run(backend, ['systemctl', '--user', 'unset-environment', *owned], deadline)
                after = backend.selected_manager_environment()
                if any(key in after for key in owned):
                    raise ValueError('Owned systemd environment remains after cleanup')
                ready_path.unlink()
            # logind can retain a logged-out session while background applications
            # finish. Record only a successfully cleaned independent session.
            if record.phase == 'ready' and record.compositor is not None:
                present = {item['Id'] for item in backend.sessions()}
                receipts = [(old, compositor) for old, compositor in completed_logins(backend)
                            if old.boot_id == owner.boot_id and old.session_id in present
                            and old.session_id != owner.session_id]
                receipts.append((owner, record.compositor))
                write_private_json(backend.runtime / 'completed.json', {'sessions': [
                    {'owner': asdict(old), 'compositor': asdict(compositor)}
                    for old, compositor in receipts]})
            (backend.runtime / 'owner.json').unlink()
    except Exception:
        # Never overwrite someone else's marker while reporting our failure.
        try:
            record = load_session(backend.runtime)
            if record.owner == owner:
                save_session(backend.runtime, replace(record, phase='failed-cleanup'))
        except (OSError, ValueError):
            pass
        raise


def stop_child(backend, child, identity, deadline):
    if child.poll() is not None:
        return
    def owned():
        return current(backend, identity) if identity is not None else backend.owns_unreaped_child(child)
    if not owned():
        raise ValueError('Tracked compositor identity changed')
    child.terminate()
    try:
        child.wait(timeout=min(5, max(0.001, deadline - time.monotonic())))
    except subprocess.TimeoutExpired:
        if child.poll() is None and owned():
            child.kill()
            child.wait(timeout=min(5, max(0.001, deadline - time.monotonic())))
        else:
            raise ValueError('Compositor identity changed during shutdown')


def start_session(backend: SessionBackend, env: Mapping[str, str]) -> int:
    prepare_runtime(backend.runtime)
    with private_lock(backend.runtime, 'lock'):
        if any((backend.runtime / name).exists() or (backend.runtime / name).is_symlink() for name in ('owner.json', 'ready.json')):
            raise ValueError('Previous ownership marker requires explicit recovery')
        deadline = time.monotonic() + READINESS_SECONDS
        with budget(backend, deadline):
            session_id = env.get('XDG_SESSION_ID', '')
            validate_login(backend, session_id, os.getpid())
            backend.validate_units()
            if any(value != 'inactive' for value in backend.unit_states((*SESSION_UNITS, SESSION_TARGET)).values()):
                raise ValueError('Legacy or unexpected desktop services active; complete first-migration prerequisite')
        owner = replace(backend.identity(os.getpid()), token=secrets.token_hex(32), session_id=session_id)
        if owner.uid != os.getuid():
            raise ValueError('Wrapper UID mismatch')
        record = SessionRecord(owner, None, 'starting', SESSION_UNITS)
        save_session(backend.runtime, record)
        child = None
        child_identity = None
        status = 1
        previous_handlers = {}
        creating_child = False
        pending_signal = None
        def interrupted(signum, frame):
            nonlocal pending_signal
            if creating_child:
                pending_signal = signum
                return
            raise InterruptedError(f'Session interrupted by signal {signum}')
        try:
            for signum in (signal.SIGTERM, signal.SIGINT):
                previous_handlers[signum] = signal.signal(signum, interrupted)
            creating_child = True
            try:
                child = backend.spawn(['/usr/bin/shoji_wm', '--tty'], {**env, 'TAB_STACK_SESSION_TOKEN': owner.token})
                child_identity = replace(backend.identity(child.pid), token=owner.token, session_id=session_id)
                if child_identity.uid != owner.uid:
                    raise ValueError('Compositor UID mismatch')
                save_session(backend.runtime, replace(record, compositor=child_identity))
            finally:
                creating_child = False
            if pending_signal is not None:
                raise InterruptedError(f'Session interrupted by signal {pending_signal}')
            while time.monotonic() < deadline:
                exited = child.poll()
                live = load_session(backend.runtime)
                if live.owner != owner:
                    raise ValueError('Session ownership changed')
                if exited is not None:
                    status = exited if live.phase == 'ready' else 1
                    break
                if live.phase == 'ready':
                    status = child.wait()
                    break
                time.sleep(0.05)
            else:
                raise ValueError('ShojiWM readiness timed out')
        except (OSError, ValueError, InterruptedError, subprocess.SubprocessError) as exc:
            print(str(exc), file=sys.stderr)
            status = 1
        finally:
            # Repeated TERM must not interrupt bounded cleanup.
            for signum in previous_handlers:
                signal.signal(signum, signal.SIG_IGN)
            failure = False
            cleanup_deadline = time.monotonic() + CLEANUP_SECONDS
            with budget(backend, cleanup_deadline):
                if child is not None:
                    try:
                        stop_child(backend, child, child_identity, cleanup_deadline)
                    except Exception:
                        failure = True
                try:
                    cleanup_session(backend, owner)
                except Exception:
                    failure = True
            if failure:
                # Even if service cleanup succeeded, an unconfirmed child blocks reuse.
                try:
                    if not (backend.runtime / 'owner.json').exists():
                        save_session(backend.runtime, replace(record, compositor=child_identity, phase='failed-cleanup'))
                    else:
                        existing = load_session(backend.runtime)
                        if existing.owner == owner:
                            save_session(backend.runtime, replace(existing, phase='failed-cleanup'))
                except (OSError, ValueError):
                    pass
                print('Session cleanup requires explicit recovery', file=sys.stderr)
                status = 1
            for signum, handler in previous_handlers.items():
                signal.signal(signum, handler)
        return status


def check_session(backend, env):
    with budget(backend, time.monotonic() + COMMAND_SECONDS):
        # Status is read-only. Launcher scopes and TTY callers need not inherit
        # the compositor's registration token or process ancestry.
        record = load_session(backend.runtime)
        if record.owner.uid != os.getuid() or not current(backend, record.owner):
            raise ValueError('Unknown or stale wrapper owner')
        if record.compositor is None or record.compositor.uid != os.getuid() or not current(backend, record.compositor):
            raise ValueError('Unknown or stale compositor')
        validate_login(backend, record.owner.session_id, record.owner.pid)
        backend.validate_units()
        ready = read_private_json(backend.runtime / 'ready.json')
        if ready.get('token') != record.owner.token or ready.get('ready') is not True:
            raise ValueError('Independent readiness lease is not verified')
        environment = ready.get('environment')
        if not isinstance(environment, dict) or any(not isinstance(value, str) for value in environment.values()):
            raise ValueError('Invalid independent readiness environment')
        selected = selected_environment(environment)
        backend.verify_peer(selected, record.compositor)
        manager = backend.selected_manager_environment()
        if any(manager.get(key) != value for key, value in selected.items()):
            raise ValueError('Independent manager environment changed')
        if record.phase != 'ready' or any(state != 'active' for state in backend.unit_states((*SESSION_UNITS, SESSION_TARGET)).values()):
            raise ValueError('Independent session is not ready')


def main():
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('start', 'ready', 'check'))
    args = parser.parse_args()
    try:
        backend = SystemBackend(os.environ)
        if args.action == 'start':
            return start_session(backend, os.environ)
        if args.action == 'ready':
            ready_session(backend, os.environ)
        else:
            check_session(backend, os.environ)
        return 0
    except (OSError, ValueError, subprocess.SubprocessError) as exc:
        print(f'tab-stack session refused: {exc}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
