"""Real boundaries for sleep_lock; imported lazily so controller tests need no D-Bus."""
import json
import os
from pathlib import Path
import signal
import socket
import subprocess
import time

import session_lifecycle as lifecycle
from session_state import load_session, read_private_json, selected_environment, process_identity

LOGIN = 'org.freedesktop.login1'
LOGIN_PATH = '/org/freedesktop/login1'
MANAGER = LOGIN + '.Manager'


def remaining(deadline, maximum=1.):
    value = min(maximum, deadline - time.monotonic())
    if value <= 0:
        raise ValueError('Sleep lock deadline expired')
    return value


def notify_systemd(ready, text):
    address = os.environ.get('NOTIFY_SOCKET')
    if not address:
        return
    if address.startswith('@'):
        address = '\0' + address[1:]
    with socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM) as client:
        client.settimeout(1)
        client.connect(address)
        client.send((('READY=1\n' if ready else '') + 'STATUS=' + text).encode())


def verify_locker(shell, environment, deadline, proc_root=Path('/proc')):
    """Match read-only IPC to a stable process on this display and exact QML path."""
    command = ['/usr/bin/quickshell', 'ipc', '--path', str(shell / 'lock.qml'), 'call', 'session', 'status']
    def query():
        reply = subprocess.run(command, capture_output=True, text=True, timeout=remaining(deadline), check=True)
        value = json.loads(reply.stdout)
        if (not isinstance(value, dict) or value.get('locked') is not True or value.get('secure') is not True
                or type(value.get('pid')) is not int or value['pid'] <= 0):
            raise ValueError('Locker is not confirmed secure')
        return value
    value = query()
    pid = value['pid']
    before = process_identity(pid, 'sleep-lock', 'locker', proc_root)
    if before.uid != os.getuid():
        raise ValueError('Foreign locker UID')
    process = proc_root / str(pid)
    if (process / 'exe').resolve().name not in ('quickshell', 'qs'):
        raise ValueError('Unexpected locker executable')
    args = (process / 'cmdline').read_bytes().decode().rstrip('\0').split('\0')
    if not any(arg in ('--path', '-p') and i+1 < len(args) and Path(args[i+1]).resolve() == (shell / 'lock.qml').resolve()
               for i, arg in enumerate(args)):
        raise ValueError('Unexpected locker QML path')
    # Read only the display value from these known process bytes; never log/store the rest.
    display = next((entry.split(b'=', 1)[1].decode() for entry in (process / 'environ').read_bytes().split(b'\0')
                    if entry.startswith(b'WAYLAND_DISPLAY=')), None)
    if display != environment.get('WAYLAND_DISPLAY'):
        raise ValueError('Foreign locker display')
    second = query()
    after = process_identity(pid, 'sleep-lock', 'locker', proc_root)
    if second['pid'] != pid or before != after:
        raise ValueError('Locker identity changed')
    return after


class LockerTask:
    """Supervise only the launcher. Its independent scope retains a detached locker."""
    def __init__(self, shell, environment, deadline):
        self.shell, self.environment, self.deadline = shell, environment, deadline
        self.process = subprocess.Popen(
            ['/usr/bin/systemd-run', '--user', '--scope', '--quiet', '--collect',
             '/usr/bin/python3', '-P', str(shell / 'lock/launch.py'), '--deadline', str(deadline)],
            env=environment, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL, close_fds=True)

    def poll(self):
        status = self.process.poll()
        if status is None:
            return None
        if status != 0:
            return False
        try:
            verify_locker(self.shell, self.environment, self.deadline)
            return True
        except (OSError, ValueError, subprocess.SubprocessError):
            return False

    def cancel(self):
        if self.process.poll() is not None:
            return
        self.process.terminate()
        try:
            self.process.wait(timeout=.3)
        except subprocess.TimeoutExpired:
            # This is the tracked direct launcher process, never its detached locker.
            self.process.kill()
            self.process.wait(timeout=.3)


class LogindBackend:
    def __init__(self, environment, require_optin=True):
        self.environment = dict(environment)
        self.session = lifecycle.SystemBackend(self.environment)
        self.shell = Path(self.environment.get('XDG_CONFIG_HOME', str(Path.home() / '.config'))) / 'shoji-shell'
        self.require_optin = require_optin
        self.bus = None
        self.matches = []
        self.generation = 0
        self.disconnected = lambda: None

    def validate(self):
        with lifecycle.budget(self.session, time.monotonic()+2):
            record = load_session(self.session.runtime)
            if (record.phase not in ('starting', 'ready') or record.compositor is None
                    or record.owner.uid != os.getuid() or record.compositor.uid != os.getuid()
                    or not lifecycle.current(self.session, record.owner)
                    or not lifecycle.current(self.session, record.compositor)):
                raise ValueError('Independent session ownership is not current')
            lifecycle.validate_login(self.session, record.owner.session_id, record.owner.pid)
            self.session.validate_units()
            if record.services != lifecycle.managed_services(self.session):
                raise ValueError('Session service lease changed')
            if self.require_optin and lifecycle.SLEEP_UNIT not in record.services:
                raise ValueError('Sleep locking is not opted in for this session')
            ready = read_private_json(self.session.runtime / 'ready.json')
            if ready.get('token') != record.owner.token or type(ready.get('ready')) is not bool:
                raise ValueError('Session readiness lease mismatch')
            selected = selected_environment(ready['environment'])
            self.session.verify_peer(selected, record.compositor)
            if self.session.selected_manager_environment() != selected:
                raise ValueError('Session display environment changed')
            self.environment.update(selected)
            self.environment['XDG_SESSION_ID'] = record.owner.session_id
            return record.owner, record.compositor, tuple(selected.items())

    def subscribe(self, callback):
        import dbus
        self.unsubscribe()
        self.bus = dbus.SystemBus(private=True)
        generation = self.generation
        def preparing(value):
            if generation == self.generation:
                callback(bool(value))
        def owner_changed(name, old, new):
            if generation == self.generation and str(name) == LOGIN and old != new:
                self.disconnected()
        def disconnected(connection):
            if generation == self.generation:
                self.disconnected()
        self.matches.append(self.bus.add_signal_receiver(preparing, signal_name='PrepareForSleep',
                                                        dbus_interface=MANAGER, bus_name=LOGIN, path=LOGIN_PATH))
        self.matches.append(self.bus.add_signal_receiver(owner_changed, signal_name='NameOwnerChanged',
                           dbus_interface='org.freedesktop.DBus', bus_name='org.freedesktop.DBus',
                           path='/org/freedesktop/DBus', arg0=LOGIN))
        self.bus.call_on_disconnection(disconnected)

    def properties(self):
        import dbus
        obj = self.bus.get_object(LOGIN, LOGIN_PATH, introspect=False)
        props = dbus.Interface(obj, 'org.freedesktop.DBus.Properties')
        maximum = int(props.Get(MANAGER, 'InhibitDelayMaxUSec', timeout=1)) / 1_000_000
        preparing = bool(props.Get(MANAGER, 'PreparingForSleep', timeout=1))
        return maximum, preparing

    def acquire(self):
        import dbus
        obj = self.bus.get_object(LOGIN, LOGIN_PATH, introspect=False)
        fd = dbus.Interface(obj, MANAGER).Inhibit('sleep', 'tab-stack', 'Secure Shoji locker before sleep', 'delay', timeout=2)
        return fd.take()

    def lock(self, deadline, context):
        environment = {key: value for key, value in self.environment.items()
                       if key not in ('NOTIFY_SOCKET', 'WATCHDOG_PID', 'WATCHDOG_USEC')}
        return LockerTask(self.shell, environment, deadline)

    def notify(self, ready, text):
        print('tab-stack sleep lock: ' + text, flush=True)
        notify_systemd(ready, text)

    def unsubscribe(self):
        self.generation += 1
        for match in self.matches:
            try: match.remove()
            except Exception: pass  # Connection may already have disappeared.
        self.matches.clear()
        bus, self.bus = self.bus, None
        if bus is not None:
            try: bus.close()
            except Exception: pass


def preflight():
    import dbus
    from dbus.mainloop.glib import DBusGMainLoop
    from gi.repository import GLib
    backend = LogindBackend(os.environ, require_optin=False)
    lifecycle.check_session(backend.session, os.environ)
    backend.validate()
    for name in ('lock/launch.py', 'lock/SessionLock.qml', 'lock/pam/shoji-lock', 'lock.qml', 'lock-check.qml'):
        if not (backend.shell / name).is_file():
            raise ValueError('Missing installed locker source')
    policy = Path('/etc/pam.d')
    if not (policy / 'shoji-lock').is_file() and not all((policy / n).is_file() for n in ('system-auth', 'system-local-login')):
        raise ValueError('Missing independent PAM policy')
    bus = dbus.SystemBus(private=True)
    try:
        props = dbus.Interface(bus.get_object(LOGIN, LOGIN_PATH, introspect=False), 'org.freedesktop.DBus.Properties')
        maximum = int(props.Get(MANAGER, 'InhibitDelayMaxUSec', timeout=2))
        if maximum <= 0: raise ValueError('Invalid delay budget')
        if bool(props.Get(MANAGER, 'PreparingForSleep', timeout=2)):
            raise ValueError('Sleep already preparing; defer preflight')
        inhibitors = dbus.Interface(bus.get_object(LOGIN, LOGIN_PATH, introspect=False), MANAGER).ListInhibitors(timeout=2)
        if any(str(row[1]) == 'tab-stack' and 'sleep' in str(row[0]).split(':') for row in inhibitors):
            raise ValueError('Another tab-stack sleep inhibitor is already present')
    finally: bus.close()
    print(f'Sleep lock preflight PASS: current session, dependencies, PAM files and logind budget {maximum / 1_000_000:g}s.')
    print('Read-only: no inhibitor, QML process, lock, authentication or sleep requested.')
    print('Live protocol and password/suspend acceptance remain separate.')


def serve():
    from dbus.mainloop.glib import DBusGMainLoop
    from gi.repository import GLib
    from sleep_lock import SleepController
    DBusGMainLoop(set_as_default=True)
    backend = LogindBackend(os.environ)
    controller = SleepController(backend)
    backend.disconnected = controller.disconnect
    loop = GLib.MainLoop()
    retry_at = 0.
    def tick():
        nonlocal retry_at
        if not controller.subscribed and time.monotonic() >= retry_at:
            try: controller.start()
            except Exception: retry_at = time.monotonic()+2
        controller.tick()
        return True
    def stop(*args):
        loop.quit()
        return GLib.SOURCE_REMOVE
    with lifecycle.private_lock(backend.session.runtime, 'sleep-monitor.lock', time.monotonic()+1):
        for signum in (signal.SIGTERM, signal.SIGINT):
            GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, signum, stop)
        GLib.timeout_add(100, tick)
        try:
            controller.start()
            loop.run()
        finally: controller.stop()
    return 0
