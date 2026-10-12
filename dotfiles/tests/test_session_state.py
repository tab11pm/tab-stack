import dataclasses
import json
import os
from pathlib import Path
import socket
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'config/shojiwm/scripts'))
import session_state as state


class OwnershipTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.proc = self.root / 'proc'
        (self.proc / 'sys/kernel/random').mkdir(parents=True)
        (self.proc / 'sys/kernel/random/boot_id').write_text('boot-a\n')
        self.pid = os.getpid()
        p = self.proc / str(self.pid)
        p.mkdir()
        (p / 'stat').write_text(f'{self.pid} (name with ) parentheses) S ' + ' '.join(['0'] * 18 + ['123']))
        (p / 'exe').symlink_to('/usr/bin/shoji_wm')
        self.owner = state.OwnerIdentity(self.pid, os.getuid(), 123, 'boot-a', 'token', '4')
        self.runtime = self.root / 'runtime'
        self.runtime.mkdir(mode=0o700)

    def test_pid_reuse_uid_and_reboot_are_not_current_owners(self):
        self.assertTrue(state.owner_is_current(self.owner, self.proc))
        for changes in ({'start_ticks': 124}, {'uid': os.getuid() + 1}, {'boot_id': 'boot-b'}, {'pid': 999999}):
            self.assertFalse(state.owner_is_current(dataclasses.replace(self.owner, **changes), self.proc))

    def test_record_roundtrip_and_private_permissions(self):
        record = state.SessionRecord(self.owner, self.owner, 'starting', ())
        state.save_session(self.runtime, record)
        self.assertEqual(state.load_session(self.runtime), record)
        self.assertEqual((self.runtime / 'owner.json').stat().st_mode & 0o777, 0o600)

    def test_malformed_symlink_and_world_readable_metadata_refused(self):
        path = self.runtime / 'owner.json'
        path.write_text('{}')
        path.chmod(0o600)
        with self.assertRaises(ValueError):
            state.load_owner(self.runtime)
        path.unlink()
        path.symlink_to(self.proc / str(self.pid) / 'stat')
        with self.assertRaises(ValueError):
            state.load_owner(self.runtime)
        path.unlink()
        state.save_session(self.runtime, state.SessionRecord(self.owner, None, 'starting', ()))
        path.chmod(0o644)
        with self.assertRaises(ValueError):
            state.load_owner(self.runtime)

    def test_graphical_conflicts_only_same_uid_user_sessions(self):
        records = [{'Id': sid, 'User': uid, 'Type': kind, 'Class': cls} for sid, uid, kind, cls in [
            ('4', str(os.getuid()), 'wayland', 'user'), ('9', str(os.getuid()), 'x11', 'user'),
            ('10', '987654', 'wayland', 'user'), ('11', str(os.getuid()), 'tty', 'user'),
            ('12', str(os.getuid()), 'unspecified', 'manager')]]
        self.assertEqual(state.conflicting_sessions(records, os.getuid(), '4'), ['9'])

    def test_environment_is_whitelisted_and_optional_values_clear(self):
        env = {'WAYLAND_DISPLAY': 'wayland-2', 'XDG_CURRENT_DESKTOP': 'ShojiWM', 'XDG_SESSION_TYPE': 'wayland', 'PRIVATE_API_KEY': 'fixture'}
        self.assertEqual(state.selected_environment(env), {
            'WAYLAND_DISPLAY': 'wayland-2', 'DISPLAY': '', 'XDG_CURRENT_DESKTOP': 'ShojiWM',
            'XDG_SESSION_TYPE': 'wayland', 'QT_QPA_PLATFORM': ''})
        for key in ('WAYLAND_DISPLAY', 'XDG_CURRENT_DESKTOP', 'XDG_SESSION_TYPE'):
            with self.assertRaises(ValueError):
                state.selected_environment({**env, key: ''})

    def test_real_unix_peer_requires_compositor_identity_and_executable(self):
        server = socket.socket(socket.AF_UNIX)
        self.addCleanup(server.close)
        try:
            server.bind(str(self.runtime / 'wayland-test'))
        except PermissionError:
            self.skipTest('Sandbox forbids Unix socket bind; host peer check pending')
        server.listen()
        with patch.object(state, 'PROC_ROOT', self.proc):
            state.verify_wayland_peer('wayland-test', self.runtime, os.getuid(), self.owner)
            for changes in ({'pid': 999999}, {'start_ticks': 124}, {'uid': os.getuid() + 1}):
                with self.assertRaises(ValueError):
                    state.verify_wayland_peer('wayland-test', self.runtime, os.getuid(), dataclasses.replace(self.owner, **changes))
            executable = self.proc / str(self.pid) / 'exe'
            executable.unlink()
            executable.symlink_to('/usr/bin/other')
            with self.assertRaises(ValueError):
                state.verify_wayland_peer('wayland-test', self.runtime, os.getuid(), self.owner)


if __name__ == '__main__':
    unittest.main()
