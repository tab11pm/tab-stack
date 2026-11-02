"""Process and D-Bus boundary tests; never invoke a real lock or inhibitor."""
from dataclasses import replace
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'config/shojiwm/scripts'))
import sleep_lock_runtime as runtime
import session_state as state


class LockerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.addCleanup(self.temp.cleanup)
        self.shell = Path(self.temp.name) / 'shell'; self.shell.mkdir()
        self.proc = Path(self.temp.name) / 'proc'; self.proc.mkdir()
        self.pid = 12345
        self.identity = state.OwnerIdentity(self.pid, os.getuid(), 70, 'boot', 't', '4')
        directory = self.proc / str(self.pid); directory.mkdir()
        (directory / 'exe').symlink_to('/usr/bin/quickshell')
        (directory / 'cmdline').write_bytes(('quickshell\0--path\0'+str(self.shell / 'lock.qml')+'\0').encode())
        (directory / 'environ').write_bytes(b'WAYLAND_DISPLAY=wayland-test\0SECRET=must-not-be-returned\0')
    def verify(self, status, identities=None):
        result = subprocess.CompletedProcess([], 0, json.dumps(status), '')
        with patch.object(runtime.subprocess, 'run', return_value=result), patch.object(runtime, 'process_identity', side_effect=identities or [self.identity, self.identity]):
            return runtime.verify_locker(self.shell, {'WAYLAND_DISPLAY': 'wayland-test'}, runtime.time.monotonic()+2, self.proc)
    def test_status_must_be_secure_object_with_integer_pid(self):
        for result in ({'secure': True, 'locked': False, 'pid': self.pid}, {'secure': 'true', 'locked': True, 'pid': self.pid}, {'secure': True, 'locked': True, 'pid': True}, [], None):
            with self.subTest(result=result), self.assertRaises(ValueError): self.verify(result)
    def test_matching_process_is_checked_before_and_after_ipc(self):
        self.assertEqual(self.verify({'secure': True, 'locked': True, 'pid': self.pid}), self.identity)
    def test_reused_pid_or_foreign_uid_is_refused(self):
        good = {'secure': True, 'locked': True, 'pid': self.pid}
        for identity in (replace(self.identity, start_ticks=71), replace(self.identity, uid=os.getuid()+1)):
            with self.subTest(identity=identity), self.assertRaises(ValueError):
                self.verify(good, [self.identity, identity])
    def test_wrong_display_or_configuration_path_is_refused(self):
        status = {'secure': True, 'locked': True, 'pid': self.pid}
        (self.proc / str(self.pid) / 'environ').write_bytes(b'WAYLAND_DISPLAY=wayland-foreign\0')
        with self.assertRaises(ValueError): self.verify(status)
        (self.proc / str(self.pid) / 'environ').write_bytes(b'WAYLAND_DISPLAY=wayland-test\0')
        (self.proc / str(self.pid) / 'cmdline').write_bytes(b'quickshell\0--path\0/other/lock.qml\0')
        with self.assertRaises(ValueError): self.verify(status)


class TaskTests(unittest.TestCase):
    def test_locker_is_spawned_in_independent_scope_with_one_deadline(self):
        process = Mock(); process.poll.return_value = None
        with patch.object(runtime.subprocess, 'Popen', return_value=process) as spawn:
            task = runtime.LockerTask(Path('/fixture/shell'), {}, runtime.time.monotonic()+3)
            argv = spawn.call_args.args[0]
            self.assertEqual(argv[:5], ['/usr/bin/systemd-run', '--user', '--scope', '--quiet', '--collect'])
            self.assertIn('--deadline', argv); self.assertNotIn('shell', spawn.call_args.kwargs)
            task.cancel(); process.terminate.assert_called_once()
    def test_exit_success_alone_is_not_proof_of_secure(self):
        process = Mock(); process.poll.return_value = 0
        with patch.object(runtime.subprocess, 'Popen', return_value=process), patch.object(runtime, 'verify_locker', side_effect=ValueError):
            task = runtime.LockerTask(Path('/fixture/shell'), {}, runtime.time.monotonic()+3)
            self.assertFalse(task.poll())
    def test_finished_launcher_is_never_signalled(self):
        process = Mock(); process.poll.return_value = 0
        with patch.object(runtime.subprocess, 'Popen', return_value=process):
            task = runtime.LockerTask(Path('/fixture/shell'), {}, runtime.time.monotonic()+3)
            task.cancel(); process.terminate.assert_not_called(); process.kill.assert_not_called()


class NotificationTests(unittest.TestCase):
    def test_ready_notification_goes_to_only_configured_socket(self):
        send = Mock()
        with patch.object(runtime.socket, 'socket') as create:
            create.return_value.__enter__.return_value = send
            with patch.dict(os.environ, {'NOTIFY_SOCKET': '@fixture-notify'}): runtime.notify_systemd(True, 'ready: verified')
        send.connect.assert_called_once_with('\0fixture-notify')
        self.assertIn(b'READY=1', send.send.call_args.args[0])


if __name__ == '__main__': unittest.main()
