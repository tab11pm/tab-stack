import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
import session_install as transaction
spec = importlib.util.spec_from_file_location('migrate_session', ROOT / 'scripts/migrate-session.py')
migration = importlib.util.module_from_spec(spec)
spec.loader.exec_module(migration)


class InstallTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name) / 'user home'
        self.home.mkdir()

    def invoke(self, *args):
        return subprocess.run([sys.executable, str(ROOT / 'scripts/install.py'), '--target-home', str(self.home), *args], text=True, capture_output=True)

    def test_default_and_session_preview_write_nothing(self):
        for args in ((), ('--component', 'session')):
            result = self.invoke(*args)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(list(self.home.iterdir()), [])
        self.assertNotIn('config/systemd/user', self.invoke('--component', 'shojiwm').stdout)

    def test_session_install_has_exact_paths_and_leaves_other_settings(self):
        sentinel = self.home / '.config/shojiwm/src/index.tsx'
        sentinel.parent.mkdir(parents=True)
        sentinel.write_text('custom monitors')
        result = self.invoke('--component', 'session', '--apply')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(sentinel.read_text(), 'custom monitors')
        expected = {'.local/bin/tab-stack-session', '.config/shojiwm/scripts/session_state.py', '.config/shojiwm/scripts/session_lifecycle.py', '.config/systemd/user/tab-stack-session.target', '.config/systemd/user/elephant.service'}
        expected.add(f'.local/lib/python{sys.version_info.major}.{sys.version_info.minor}/site-packages/tab_stack_session.py')
        expected.update('.config/systemd/user/'+unit+'.d/tab-stack-session.conf' for unit in ('xdg-desktop-portal.service', 'xdg-desktop-portal-gtk.service', 'xdg-desktop-portal-wlr.service', 'xdg-desktop-portal-shojiwm.service'))
        actual = {str(p.relative_to(self.home)) for p in self.home.rglob('*') if p.is_file() and '.local/state/' not in str(p.relative_to(self.home)) and p != sentinel}
        self.assertEqual(actual, expected)
        self.assertEqual((self.home / '.local/bin/tab-stack-session').stat().st_mode & 0o777, 0o755)

    def test_unknown_existing_unit_and_symlink_refused_before_any_install(self):
        path = self.home / '.config/systemd/user/elephant.service'
        path.parent.mkdir(parents=True)
        path.write_text('custom unit')
        result = self.invoke('--component', 'session', '--apply')
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.home / '.local/bin/tab-stack-session').exists())
        self.assertEqual(path.read_text(), 'custom unit')
        path.unlink(); path.symlink_to('/missing')
        result = self.invoke('--component', 'session', '--apply')
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.home / '.local/bin/tab-stack-session').exists())

    def old_profile(self):
        index = subprocess.run(['git', 'show', '4cbf9bb:dotfiles/config/shojiwm/src/index.tsx'], cwd=ROOT, capture_output=True, text=True, check=True).stdout
        qml = subprocess.run(['git', 'show', '4cbf9bb:dotfiles/config/shoji-shell/HomeSystemCard.qml'], cwd=ROOT, capture_output=True, text=True, check=True).stdout
        a = self.home / '.config/shojiwm/src/index.tsx'; a.parent.mkdir(parents=True)
        b = self.home / '.config/shoji-shell/HomeSystemCard.qml'; b.parent.mkdir(parents=True)
        a.write_text('// custom monitor hook\n'+index); b.write_text('// custom colours\n'+qml)
        a.chmod(0o640); b.chmod(0o644)
        return a, b

    def test_minimal_migration_preview_apply_and_guarded_rollback(self):
        a, b = self.old_profile(); before = {p: p.read_bytes() for p in (a, b)}
        changes = migration.preview(self.home)
        self.assertEqual({p: p.read_bytes() for p in before}, before)
        manifest = migration.apply(self.home)
        self.assertTrue(a.read_text().startswith('// custom monitor hook\n'))
        self.assertTrue(b.read_text().startswith('// custom colours\n'))
        self.assertIn('session_lifecycle.py', a.read_text())
        self.assertIn('../shojiwm/scripts/logout', b.read_text())
        b.write_text(b.read_text()+'// later edit\n')
        installed_a = a.read_bytes()
        with self.assertRaises(ValueError):
            transaction.rollback(manifest)
        self.assertEqual(a.read_bytes(), installed_a)
        b.write_bytes(changes[b][0])
        transaction.rollback(manifest)
        self.assertEqual({p: p.read_bytes() for p in before}, before)
        self.assertEqual(a.stat().st_mode & 0o777, 0o640)
        self.assertFalse((self.home / '.local/state/tab-stack/session/tab-stack.desktop').exists())

    def test_unknown_second_hunk_prevents_first_file_write(self):
        a, b = self.old_profile(); previous = a.read_bytes()
        b.write_text('unknown custom shell')
        with self.assertRaises(ValueError): migration.apply(self.home)
        self.assertEqual(a.read_bytes(), previous)
        self.assertFalse((self.home / '.local/state').exists())

    def test_partial_io_failure_rolls_back_own_changes(self):
        a, b = self.old_profile(); before = {p: p.read_bytes() for p in (a, b)}
        real = transaction.atomic_write
        count = 0
        def fail_once(path, data, mode):
            nonlocal count
            if path in before:
                count += 1
                if count == 2: raise OSError('fixture disk failure')
            return real(path, data, mode)
        with patch.object(transaction, 'atomic_write', fail_once):
            with self.assertRaises(OSError): migration.apply(self.home)
        self.assertEqual({p: p.read_bytes() for p in before}, before)

    def test_desktop_path_escaping_and_validation(self):
        for name in ('user home', 'имя', 'quote"slash\\dollar$percent%tick`'):
            executable = Path('/fixture') / name / '.local/bin/tab-stack-session'
            entry = migration.render_desktop_entry(executable)
            path = Path(self.temp.name) / 'tab-stack.desktop'; path.write_text(entry)
            result = subprocess.run(['desktop-file-validate', str(path)], capture_output=True, text=True)
            diagnostics = result.stdout + result.stderr
            # DesktopNames is a display-manager extension absent from this validator.
            errors = [line for line in diagnostics.splitlines() if 'error:' in line]
            self.assertTrue(all('key "DesktopNames"' in line for line in errors), diagnostics)
            path.write_text(entry.replace('DesktopNames=ShojiWM\n', ''))
            standard = subprocess.run(['desktop-file-validate', str(path)], capture_output=True, text=True)
            self.assertEqual(standard.returncode, 0, standard.stdout + standard.stderr)
            self.assertIn('Exec=/usr/bin/python3 -P -m tab_stack_session start\n', entry)
        for name in ('bad=path', 'bad\npath'):
            with self.assertRaises(ValueError): migration.render_desktop_entry(Path('/fixture') / name)

    def test_session_entry_executes_through_sddm_consumer_with_unusual_home(self):
        import shlex
        for name in ('plain', 'space user', 'имя$quote"percent%back\\tick`'):
            self.home = Path(self.temp.name) / name
            self.home.mkdir()
            result = self.invoke('--component', 'session', '--apply')
            self.assertEqual(result.returncode, 0, result.stderr)
            helper = self.home / '.config/shojiwm/scripts/session_lifecycle.py'
            helper.write_text('import json,sys; print(json.dumps(sys.argv[1:]))\n')
            raw = next(line[5:] for line in migration.render_desktop_entry(self.home / '.local/bin/tab-stack-session').splitlines() if line.startswith('Exec='))
            # SDDM 0.21 passes raw Exec as ONE arg; shipped session script does exec $@.
            env = {**os.environ, 'HOME': str(self.home)}
            for key in ('PYTHONPATH', 'PYTHONUSERBASE', 'PYTHONNOUSERSITE', 'XDG_CONFIG_HOME'):
                env.pop(key, None)
            launched = subprocess.run(['/bin/sh', '-c', 'exec $@', 'sddm-session', raw], env=env, text=True, capture_output=True)
            self.assertEqual(launched.returncode, 0, launched.stderr)
            self.assertEqual(json.loads(launched.stdout), ['start'])

    def test_automatic_rollback_preserves_concurrent_user_edit(self):
        a, b = self.old_profile()
        real = transaction.atomic_write
        def fail_after_edit(path, data, mode):
            if path == b:
                a.write_text('concurrent user edit')
                raise OSError('fixture disk failure')
            return real(path, data, mode)
        with patch.object(transaction, 'atomic_write', fail_after_edit):
            with self.assertRaises(OSError): migration.apply(self.home)
        self.assertEqual(a.read_text(), 'concurrent user edit')
        manifest = next((self.home / '.local/state/tab-stack/backups').glob('*/manifest.json'))
        self.assertEqual(json.loads(manifest.read_text())['status'], 'recovery-required')

    def test_explicit_rollback_rechecks_each_target_after_batch_preflight(self):
        a, b = self.old_profile()
        manifest = migration.apply(self.home)
        real = transaction.restore
        def intervene(entry):
            real(entry)
            if Path(entry['target']) == b:
                a.write_text('concurrent second edit')
        with patch.object(transaction, 'restore', intervene):
            with self.assertRaises(ValueError): transaction.rollback(manifest)
        self.assertEqual(a.read_text(), 'concurrent second edit')

    def test_session_component_preserves_user_only_apply_guard(self):
        import runpy
        argv = ['install.py', '--component', 'session', '--target-home', str(self.home), '--apply']
        with patch.object(sys, 'argv', argv), patch('os.geteuid', return_value=0):
            with self.assertRaises(SystemExit) as outcome:
                runpy.run_path(str(ROOT / 'scripts/install.py'), run_name='__main__')
            self.assertEqual(outcome.exception.code, 2)
        self.assertEqual(list(self.home.iterdir()), [])
