import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
import session_install as transaction


class SleepInstallTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name) / 'user home'; self.home.mkdir()
    def invoke(self, *args):
        return subprocess.run([sys.executable, str(ROOT / 'scripts/install.py'), '--target-home', str(self.home), *args], capture_output=True, text=True)
    def baseline(self):
        result = self.invoke('--component', 'session', '--apply')
        self.assertEqual(result.returncode, 0, result.stderr)
        for name in ('lock/launch.py', 'lock/SessionLock.qml', 'lock/pam/shoji-lock', 'lock.qml', 'lock-check.qml'):
            target = self.home / '.config/shoji-shell' / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes((ROOT / 'config/shoji-shell' / name).read_bytes())
    def test_preview_is_write_free_and_missing_session_is_refused(self):
        result = self.invoke('--component', 'sleep-lock')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(list(self.home.iterdir()), [])
        self.baseline(); before = {p:p.read_bytes() for p in self.home.rglob('*') if p.is_file()}
        result = self.invoke('--component', 'sleep-lock')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual({p:p.read_bytes() for p in self.home.rglob('*') if p.is_file()}, before)
    def test_optin_installs_exact_delta_preserves_profiles_and_rolls_back(self):
        self.baseline()
        sentinel = self.home / '.config/shoji-shell/idle-sleep.json'; sentinel.write_text('{"enabled":false}')
        before = {p:p.read_bytes() for p in self.home.rglob('*') if p.is_file()}
        result = self.invoke('--component', 'sleep-lock', '--apply')
        self.assertEqual(result.returncode, 0, result.stderr)
        new = {p for p in self.home.rglob('*') if p.is_file()} - before.keys()
        new = {str(p.relative_to(self.home)) for p in new if '.local/state/' not in str(p.relative_to(self.home))}
        self.assertEqual(new, {'.config/shojiwm/scripts/sleep_lock.py', '.config/shojiwm/scripts/sleep_lock_runtime.py',
            '.config/systemd/user/tab-stack-sleep-lock.service', '.config/systemd/user/tab-stack-session.target.d/sleep-lock.conf'})
        self.assertEqual(sentinel.read_text(), '{"enabled":false}')
        manifest = Path(result.stdout.split('Sleep lock manifest: ',1)[1].strip())
        result = self.invoke('--rollback', str(manifest)); self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual({p:p.read_bytes() for p in before}, before)
        self.assertFalse((self.home / '.config/systemd/user/tab-stack-sleep-lock.service').exists())
    def test_unknown_locker_and_symlink_prevent_any_delta(self):
        self.baseline(); target = self.home / '.config/shoji-shell/lock/SessionLock.qml'
        target.write_text('custom locker')
        result = self.invoke('--component', 'sleep-lock', '--apply')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(target.read_text(), 'custom locker')
        self.assertFalse((self.home / '.config/shojiwm/scripts/sleep_lock.py').exists())
        target.unlink(); target.symlink_to(ROOT / 'config/shoji-shell/lock/SessionLock.qml')
        self.assertNotEqual(self.invoke('--component', 'sleep-lock', '--apply').returncode, 0)
    def test_rollback_refuses_later_edits_before_restoring_other_files(self):
        self.baseline(); result = self.invoke('--component', 'sleep-lock', '--apply')
        self.assertEqual(result.returncode, 0, result.stderr)
        manifest = Path(result.stdout.split('Sleep lock manifest: ',1)[1].strip())
        target = self.home / '.config/systemd/user/tab-stack-session.target.d/sleep-lock.conf'
        target.write_text('later edit')
        self.assertNotEqual(self.invoke('--rollback', str(manifest)).returncode, 0)
        self.assertEqual(target.read_text(), 'later edit')
        self.assertTrue((self.home / '.config/shojiwm/scripts/sleep_lock.py').is_file())
    def test_plain_session_install_does_not_enable_sleep_lock(self):
        self.baseline()
        self.assertFalse((self.home / '.config/systemd/user/tab-stack-sleep-lock.service').exists())
        self.assertFalse((self.home / '.config/systemd/user/tab-stack-session.target.d').exists())


if __name__ == '__main__': unittest.main()
