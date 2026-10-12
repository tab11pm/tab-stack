"""External logind/systemd/process boundary fixture; production state stays real."""
from dataclasses import replace
import os
from pathlib import Path
import subprocess
import session_state as state

UNITS = ('elephant.service', 'xdg-desktop-portal.service', 'xdg-desktop-portal-gtk.service', 'xdg-desktop-portal-wlr.service', 'xdg-desktop-portal-shojiwm.service')
TARGET = 'tab-stack-session.target'


class Child:
    pid = 42424
    def __init__(self, backend):
        self.backend = backend
        self.status = None
    def poll(self):
        if self.backend.exit_before_ready:
            return 7
        if self.backend.ready_on_poll and self.status is None:
            self.backend.ready_on_poll = False
            import session_lifecycle as lifecycle
            lifecycle.ready_session(self.backend, self.backend.spawn_env)
            self.status = 3
        return self.status
    def terminate(self):
        self.status = -15
    def kill(self):
        self.status = -9
    def wait(self, timeout):
        return self.status


class Backend:
    def __init__(self, runtime):
        self.runtime = Path(runtime) / 'tab-stack-session'
        self.environment = {'XDG_RUNTIME_DIR': str(runtime), 'XDG_SESSION_ID': '4',
                            'XDG_CURRENT_DESKTOP': 'ShojiWM', 'XDG_SESSION_TYPE': 'wayland',
                            'WAYLAND_DISPLAY': 'wayland-test', 'DISPLAY': ':2'}
        self.owner = state.OwnerIdentity(os.getpid(), os.getuid(), 123, 'boot', 'fixture', '4')
        self.child_identity = replace(self.owner, pid=Child.pid)
        self.records = [{'Id': '4', 'User': str(os.getuid()), 'Type': 'wayland', 'Class': 'user', 'State': 'active', 'Leader': str(os.getpid())}]
        self.states = {unit: 'inactive' for unit in (*UNITS, TARGET)}
        self.manager = {}
        self.activation = {}
        self.import_sets_manager = True
        self.calls = []
        self.spawn_env = None
        self.fail_command = None
        self.fail_unit = None
        self.peer_valid = True
        self.caller_valid = True
        self.ready_on_poll = True
        self.exit_before_ready = False
        self.child = Child(self)
    def sessions(self):
        return self.records
    def identity(self, pid):
        return self.child_identity if pid == Child.pid else self.owner
    def unit_states(self, names):
        return {name: self.states[name] for name in names}
    def selected_manager_environment(self):
        return self.manager.copy()
    def validate_units(self):
        pass
    def descendant(self, pid, ancestor):
        return self.caller_valid
    def verify_peer(self, env, identity):
        if not self.peer_valid:
            raise ValueError('Wrong Wayland peer')
    def command(self, argv, env=None, timeout=10):
        self.calls.append((argv, timeout))
        if self.fail_command and self.fail_command in argv:
            raise subprocess.TimeoutExpired(argv, timeout)
        if argv[:3] == ['systemctl', '--user', 'start']:
            self.states[TARGET] = 'active'
            for unit in UNITS:
                self.states[unit] = 'failed' if unit == self.fail_unit else 'active'
        elif argv[:3] == ['systemctl', '--user', 'stop']:
            for unit in argv[3:]:
                self.states[unit] = 'inactive'
            if TARGET in argv:
                for unit in UNITS:
                    self.states[unit] = 'inactive'
        elif argv[0] == 'dbus-update-activation-environment':
            values = dict(item.split('=', 1) for item in argv[2 if argv[1] == '--systemd' else 1:])
            self.activation.update(values)
            if argv[1] == '--systemd' and self.import_sets_manager:
                self.manager.update(values)
        elif argv[:3] == ['systemctl', '--user', 'unset-environment']:
            for key in argv[3:]:
                self.manager.pop(key, None)
        return subprocess.CompletedProcess(argv, 0, '', '')
    def spawn(self, argv, env):
        if argv != ['/usr/bin/shoji_wm', '--tty']:
            raise AssertionError('Unexpected compositor command')
        self.spawn_env = dict(env)
        return self.child

    def owns_unreaped_child(self, child):
        return child is self.child and child.status is None
