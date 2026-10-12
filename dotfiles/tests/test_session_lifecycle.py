import configparser
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
UNITS = ('elephant.service', 'xdg-desktop-portal.service', 'xdg-desktop-portal-gtk.service', 'xdg-desktop-portal-wlr.service', 'xdg-desktop-portal-shojiwm.service')


class UnitOwnershipTests(unittest.TestCase):
    def read_unit(self, name):
        p = ROOT / 'config/systemd/user' / name
        self.assertTrue(p.is_file(), f'Missing session ownership definition: {name}')
        parser = configparser.ConfigParser(interpolation=None)
        parser.read(p)
        return parser

    def test_stop_lease_contains_only_explicit_desktop_services(self):
        target = self.read_unit('tab-stack-session.target')
        self.assertEqual(set(target['Unit']['Wants'].split()), set(UNITS))
        self.assertEqual(target['Unit']['StopWhenUnneeded'], 'no')
        self.assertNotIn('Install', target)
        self.assertFalse(any(key in target['Unit'] for key in ('Requires', 'BindsTo', 'PartOf')))
        for unit in UNITS:
            source = unit if unit == 'elephant.service' else unit + '.d/tab-stack-session.conf'
            definition = self.read_unit(source)
            self.assertEqual(definition['Unit']['PartOf'].split(), ['tab-stack-session.target'])
            self.assertEqual(definition['Service']['TimeoutStopSec'], '10s')
            self.assertNotIn('Install', definition)

    def test_elephant_runs_portable_executable_with_bounded_restart(self):
        definition = self.read_unit('elephant.service')
        self.assertEqual(definition['Service']['ExecStart'], '/usr/bin/elephant')
        self.assertEqual(definition['Service']['Restart'], 'on-failure')
        self.assertEqual(definition['Service']['RestartSec'], '2')


if __name__ == '__main__':
    unittest.main()

# These tests catch takeover, partial startup leakage, and stale environment cleanup.
import dataclasses
import fcntl
import os
import sys
import tempfile
from unittest.mock import patch
sys.path.insert(0, str(ROOT / 'config/shojiwm/scripts'))
import session_state as state
import session_lifecycle as lifecycle
from session_fixtures import Backend, TARGET


class ManagerEnvironmentTests(unittest.TestCase):
    def parse(self, output):
        import subprocess
        backend = lifecycle.SystemBackend.__new__(lifecycle.SystemBackend)
        backend.command = lambda *args: subprocess.CompletedProcess(args[0], 0, output, '')
        return backend.selected_manager_environment()

    def test_systemd_values_decode_without_shell_execution_or_unrelated_parsing(self):
        for encoded, expected in [
            ("$'wayland;xcb'", 'wayland;xcb'),
            (r"$'quote\' slash\\ hex\x3b octal\073'", "quote' slash\\ hex; octal;"),
            ("$'путь $(touch /not-executed)'", 'путь $(touch /not-executed)'),
            ("$''", ''),
            ("'wayland;xcb'", 'wayland;xcb'),
            ('wayland', 'wayland'),
        ]:
            with self.subTest(encoded=encoded):
                self.assertEqual(self.parse('UNRELATED=$\'unterminated\nQT_QPA_PLATFORM='+encoded),
                                 {'QT_QPA_PLATFORM': expected})

    def test_malformed_selected_dollar_quoted_value_is_refused(self):
        for value in ("$'unterminated", "$'x'; touch /not-executed", "$'x' + 1"):
            with self.subTest(value=value), self.assertRaises(ValueError):
                self.parse('QT_QPA_PLATFORM='+value)


class LifecycleTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.backend = Backend(self.temp.name)

    def ready_record(self):
        b = self.backend
        state.prepare_runtime(b.runtime)
        state.save_session(b.runtime, state.SessionRecord(b.owner, b.child_identity, 'starting', UNITS))
        return {**b.environment, 'TAB_STACK_SESSION_TOKEN': b.owner.token}

    def test_systemd_dollar_quoted_platform_reaches_ready_and_cleans_up(self):
        import subprocess
        from types import MethodType
        b = self.backend
        b.environment['QT_QPA_PLATFORM'] = 'wayland;xcb'
        env = self.ready_record()
        real = b.command
        def command(argv, env=None, timeout=10):
            if argv == ['systemctl', '--user', 'show-environment']:
                lines = [key + '=' + ("$'wayland;xcb'" if key == 'QT_QPA_PLATFORM' else value)
                         for key, value in b.manager.items()]
                return subprocess.CompletedProcess(argv, 0, '\n'.join(lines), '')
            return real(argv, env, timeout)
        b.command = command
        b.selected_manager_environment = MethodType(lifecycle.SystemBackend.selected_manager_environment, b)
        lifecycle.ready_session(b, env)
        self.assertEqual(state.load_session(b.runtime).phase, 'ready')
        self.assertTrue(all(value == 'active' for value in b.states.values()))
        self.assertEqual(b.selected_manager_environment()['QT_QPA_PLATFORM'], 'wayland;xcb')
        lifecycle.cleanup_session(b, b.owner)
        self.assertFalse((b.runtime / 'owner.json').exists())
        self.assertEqual(b.manager, {})

    def test_other_graphical_login_is_not_stopped(self):
        b = self.backend
        b.records.append({'Id': '9', 'User': str(os.getuid()), 'Type': 'x11', 'Class': 'user'})
        with self.assertRaises(ValueError):
            lifecycle.start_session(b, b.environment)
        self.assertIsNone(b.spawn_env)
        self.assertEqual(b.calls, [])

    def next_login(self, previous, sid):
        b = Backend(self.temp.name)
        b.owner = dataclasses.replace(b.owner, start_ticks=previous.owner.start_ticks + 1, session_id=sid)
        b.child_identity = dataclasses.replace(b.owner, pid=b.child.pid)
        b.environment['XDG_SESSION_ID'] = sid
        b.records = [{**record, 'State': 'closing'} for record in previous.records]
        b.records.append({'Id': sid, 'User': str(os.getuid()), 'Type': 'wayland',
                          'Class': 'user', 'State': 'active', 'Leader': str(os.getpid())})
        return b

    def test_completed_logout_allows_relogin_with_persistent_closing_sessions(self):
        first = self.backend
        self.assertEqual(lifecycle.start_session(first, first.environment), 3)
        second = self.next_login(first, '8')
        try:
            second_status = lifecycle.start_session(second, second.environment)
        except ValueError as exc:
            self.fail(f'Completed session still blocks the next login: {exc}')
        self.assertEqual(second_status, 3)
        third = self.next_login(second, '12')
        self.assertEqual(lifecycle.start_session(third, third.environment), 3)
        self.assertTrue(all(value == 'inactive' for value in third.states.values()))
        self.assertFalse((third.runtime / 'owner.json').exists())

    def test_completed_receipt_does_not_allow_an_active_old_login(self):
        first = self.backend
        lifecycle.start_session(first, first.environment)
        second = self.next_login(first, '8')
        second.records[0]['State'] = 'active'
        with self.assertRaises(ValueError): lifecycle.start_session(second, second.environment)
        self.assertIsNone(second.spawn_env)
        self.assertEqual(second.calls, [])

    def test_completed_receipt_does_not_allow_a_live_old_compositor(self):
        first = self.backend
        lifecycle.start_session(first, first.environment)
        second = self.next_login(first, '8')
        real = second.identity
        second.identity = lambda pid: first.child_identity if pid == first.child.pid else real(pid)
        with self.assertRaises(ValueError): lifecycle.start_session(second, second.environment)
        self.assertIsNone(second.spawn_env)

    def test_completed_receipt_does_not_allow_an_unowned_closing_login(self):
        first = self.backend
        lifecycle.start_session(first, first.environment)
        second = self.next_login(first, '8')
        second.records.append({'Id': '99', 'User': str(os.getuid()), 'Type': 'wayland',
                               'Class': 'user', 'State': 'closing', 'Leader': '99999'})
        with self.assertRaises(ValueError): lifecycle.start_session(second, second.environment)
        self.assertIsNone(second.spawn_env)

    def test_completed_receipt_from_another_boot_cannot_allow_relogin(self):
        first = self.backend
        lifecycle.start_session(first, first.environment)
        second = self.next_login(first, '8')
        second.owner = dataclasses.replace(second.owner, boot_id='different-boot')
        with self.assertRaises(ValueError): lifecycle.start_session(second, second.environment)
        self.assertIsNone(second.spawn_env)

    def test_active_legacy_backend_refused_before_spawn(self):
        b = self.backend
        b.states['elephant.service'] = 'active'
        with self.assertRaises(ValueError):
            lifecycle.start_session(b, b.environment)
        self.assertEqual(b.states['elephant.service'], 'active')
        self.assertIsNone(b.spawn_env)

    def test_cleanup_resets_only_failed_owned_units_after_display_disconnect(self):
        env = self.ready_record()
        b = self.backend
        lifecycle.ready_session(b, env)
        b.states['unrelated.service'] = 'failed'
        real = b.command
        def command(argv, env=None, timeout=10):
            if argv[:3] == ['systemctl', '--user', 'reset-failed']:
                import subprocess
                b.calls.append((argv, timeout))
                for name in argv[3:]: b.states[name] = 'inactive'
                return subprocess.CompletedProcess(argv, 0, '', '')
            value = real(argv, env, timeout)
            if argv[:3] == ['systemctl', '--user', 'stop']:
                b.states['xdg-desktop-portal-gtk.service'] = 'failed'
            return value
        b.command = command
        lifecycle.cleanup_session(b, b.owner)
        self.assertEqual(b.states['xdg-desktop-portal-gtk.service'], 'inactive')
        self.assertEqual(b.states['unrelated.service'], 'failed')
        reset = [argv for argv, _ in b.calls if argv[:3] == ['systemctl', '--user', 'reset-failed']]
        self.assertEqual(reset, [['systemctl', '--user', 'reset-failed', 'xdg-desktop-portal-gtk.service']])
        self.assertFalse((b.runtime / 'owner.json').exists())

    def test_failed_status_reset_preserves_cleanup_failure_marker(self):
        env = self.ready_record()
        b = self.backend
        lifecycle.ready_session(b, env)
        real = b.command
        def command(argv, env=None, timeout=10):
            if argv[:3] == ['systemctl', '--user', 'reset-failed']:
                raise ValueError('Reset failed')
            value = real(argv, env, timeout)
            if argv[:3] == ['systemctl', '--user', 'stop']:
                b.states['xdg-desktop-portal-gtk.service'] = 'failed'
            return value
        b.command = command
        with self.assertRaises(ValueError): lifecycle.cleanup_session(b, b.owner)
        self.assertEqual(state.load_session(b.runtime).phase, 'failed-cleanup')
        self.assertTrue((b.runtime / 'ready.json').exists())
        self.assertFalse((b.runtime / 'completed.json').exists())

    def test_duplicate_lock_and_stale_marker_refused(self):
        b = self.backend
        state.prepare_runtime(b.runtime)
        with (b.runtime / 'lock').open('w') as lock:
            os.chmod(lock.name, 0o600)
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            with self.assertRaises(ValueError):
                lifecycle.start_session(b, b.environment)
        state.save_session(b.runtime, state.SessionRecord(b.owner, None, 'failed-cleanup', ()))
        with self.assertRaises(ValueError):
            lifecycle.start_session(b, b.environment)
        self.assertEqual(b.calls, [])

    def test_wrong_token_caller_peer_and_environment_cause_no_service_writes(self):
        env = self.ready_record()
        b = self.backend
        for case in ('token', 'caller', 'peer', 'environment', 'reused'):
            with self.subTest(case=case):
                b.caller_valid = case != 'caller'
                b.peer_valid = case != 'peer'
                b.owner = dataclasses.replace(b.owner, start_ticks=124 if case == 'reused' else 123)
                invalid = dict(env)
                if case == 'token': invalid['TAB_STACK_SESSION_TOKEN'] = 'wrong'
                if case == 'environment': invalid.pop('WAYLAND_DISPLAY')
                with self.assertRaises(ValueError):
                    lifecycle.ready_session(b, invalid)
                self.assertEqual(b.calls, [])

    def test_ready_imports_before_service_refresh_and_duplicate_is_idempotent(self):
        env = self.ready_record()
        b = self.backend
        b.states['xdg-desktop-portal.service'] = 'active'  # D-Bus startup since baseline.
        lifecycle.ready_session(b, env)
        self.assertEqual(state.load_session(b.runtime).phase, 'ready')
        self.assertEqual(b.manager['DISPLAY'], ':2')
        self.assertEqual(b.calls[0][0][:2], ['dbus-update-activation-environment', '--systemd'])
        self.assertTrue(all(b.states[u] == 'active' for u in UNITS))
        previous = len(b.calls)
        lifecycle.ready_session(b, env)
        self.assertEqual(len(b.calls), previous)

    def test_failed_service_does_not_signal_success_and_partial_import_is_owned(self):
        env = self.ready_record()
        b = self.backend
        b.fail_unit = 'elephant.service'
        with self.assertRaises(ValueError):
            lifecycle.ready_session(b, env)
        self.assertNotEqual(state.load_session(b.runtime).phase, 'ready')
        lifecycle.cleanup_session(b, b.owner)
        self.assertFalse((b.runtime / 'owner.json').exists())
        self.assertEqual(b.manager, {})
        self.assertTrue(all(b.states[u] == 'inactive' for u in UNITS))

    def test_cleanup_preserves_changed_foreign_values_and_invalidates_owned_dbus_values(self):
        env = self.ready_record()
        b = self.backend
        lifecycle.ready_session(b, env)
        b.manager['DISPLAY'] = ':foreign'
        lifecycle.cleanup_session(b, b.owner)
        self.assertEqual(b.manager, {'DISPLAY': ':foreign'})
        invalidation = next(argv for argv, _ in b.calls if argv[0] == 'dbus-update-activation-environment' and argv[1] != '--systemd')
        self.assertIn('WAYLAND_DISPLAY=', invalidation)
        self.assertFalse(any(arg.startswith('DISPLAY=') for arg in invalidation))

    def test_cleanup_failure_retains_guard_and_command_budget(self):
        env = self.ready_record()
        b = self.backend
        lifecycle.ready_session(b, env)
        b.fail_command = 'stop'
        with self.assertRaises(Exception):
            lifecycle.cleanup_session(b, b.owner)
        self.assertEqual(state.load_session(b.runtime).phase, 'failed-cleanup')
        self.assertTrue(all(0 < timeout <= 10 for _, timeout in b.calls))

    def test_compositor_exit_before_ready_cleans_only_owned_lease(self):
        b = self.backend
        b.exit_before_ready = True
        self.assertEqual(lifecycle.start_session(b, b.environment), 1)
        self.assertFalse((b.runtime / 'owner.json').exists())
        self.assertTrue(all(b.states[u] == 'inactive' for u in UNITS))

    def test_normal_exit_status_preserved_with_complete_cleanup(self):
        b = self.backend
        self.assertEqual(lifecycle.start_session(b, b.environment), 3)
        self.assertFalse((b.runtime / 'owner.json').exists())
        self.assertEqual(b.manager, {})
        self.assertTrue(all(b.states[u] == 'inactive' for u in UNITS))

    def test_readiness_timeout_terminates_only_tracked_child(self):
        b = self.backend
        b.ready_on_poll = False
        with patch.object(lifecycle, 'READINESS_SECONDS', 0.01):
            self.assertEqual(lifecycle.start_session(b, b.environment), 1)
        self.assertEqual(b.child.status, -15)
        self.assertFalse((b.runtime / 'owner.json').exists())

    def test_new_services_are_not_restarted_after_first_target_start(self):
        env = self.ready_record()
        lifecycle.ready_session(self.backend, env)
        self.assertFalse(any(argv[:3] == ['systemctl', '--user', 'restart'] for argv, _ in self.backend.calls))

    def test_import_failure_does_not_start_target_and_cleanup_remains_explicit(self):
        env = self.ready_record()
        b = self.backend
        b.fail_command = '--systemd'
        with self.assertRaises(Exception):
            lifecycle.ready_session(b, env)
        self.assertEqual(b.states[TARGET], 'inactive')
        self.assertTrue((b.runtime / 'ready.json').exists())
        b.fail_command = None
        lifecycle.cleanup_session(b, b.owner)
        self.assertFalse((b.runtime / 'owner.json').exists())

    def test_symlink_runtime_refused_without_service_mutation(self):
        b = self.backend
        b.runtime.symlink_to(Path(self.temp.name))
        with self.assertRaises(ValueError):
            lifecycle.start_session(b, b.environment)
        self.assertEqual(b.calls, [])

    def test_check_is_read_only(self):
        env = self.ready_record()
        lifecycle.ready_session(self.backend, env)
        before = {p.name: p.read_bytes() for p in self.backend.runtime.iterdir()}
        count = len(self.backend.calls)
        lifecycle.check_session(self.backend, env)
        self.assertEqual(before, {p.name: p.read_bytes() for p in self.backend.runtime.iterdir()})
        self.assertEqual(count, len(self.backend.calls))

    def test_cleanup_refuses_foreign_login_or_owner(self):
        env = self.ready_record()
        b = self.backend
        lifecycle.ready_session(b, env)
        before = dict(b.states)
        b.records.append({'Id': '9', 'User': str(os.getuid()), 'Type': 'wayland', 'Class': 'user'})
        with self.assertRaises(ValueError):
            lifecycle.cleanup_session(b, b.owner)
        self.assertEqual(b.states, before)
        self.assertEqual(state.load_session(b.runtime).phase, 'failed-cleanup')

    def test_status_from_launcher_or_tty_does_not_require_readiness_caller_token(self):
        b = self.backend
        env = self.ready_record()
        lifecycle.ready_session(b, env)
        before = {p.name: p.read_bytes() for p in b.runtime.iterdir()}
        calls = len(b.calls)
        for caller in ({}, {'TAB_STACK_SESSION_TOKEN': 'previous-session',
                           'WAYLAND_DISPLAY': 'obsolete-display', 'XDG_SESSION_TYPE': 'tty'}):
            with self.subTest(caller=caller), patch.object(lifecycle.os, 'getpid', return_value=999999):
                try:
                    lifecycle.check_session(b, caller)
                except ValueError as exc:
                    self.fail(f'Live session status rejected an unrelated read-only caller: {exc}')
        self.assertEqual(before, {p.name: p.read_bytes() for p in b.runtime.iterdir()})
        self.assertEqual(len(b.calls), calls)
        # Permission to read status never grants permission to register readiness.
        with self.assertRaises(ValueError): lifecycle.ready_session(b, {})

    def test_status_refuses_stale_owner_compositor_peer_or_manager_environment(self):
        b = self.backend
        env = self.ready_record()
        lifecycle.ready_session(b, env)
        old_owner, old_compositor = b.owner, b.child_identity
        for broken in ('owner', 'compositor', 'peer', 'manager'):
            with self.subTest(broken=broken):
                b.owner, b.child_identity = old_owner, old_compositor
                b.peer_valid = True
                b.manager = state.selected_environment(env)
                if broken == 'owner': b.owner = dataclasses.replace(old_owner, start_ticks=999)
                elif broken == 'compositor': b.child_identity = dataclasses.replace(old_compositor, start_ticks=999)
                elif broken == 'peer': b.peer_valid = False
                else: b.manager['DISPLAY'] = ':foreign'
                with self.assertRaises(ValueError): lifecycle.check_session(b, env)

    def test_status_refuses_a_malformed_readiness_environment(self):
        b = self.backend
        env = self.ready_record()
        lifecycle.ready_session(b, env)
        path = b.runtime / 'ready.json'
        value = state.read_private_json(path)
        value['environment'] = 'not-an-environment'
        state.write_private_json(path, value)
        with self.assertRaises(ValueError): lifecycle.check_session(b, env)

    def test_nonfatal_systemd_import_failure_is_not_readiness_and_dbus_is_cleaned(self):
        env = self.ready_record()
        b = self.backend
        b.import_sets_manager = False
        with self.assertRaises(ValueError): lifecycle.ready_session(b, env)
        self.assertEqual(b.states[TARGET], 'inactive')
        self.assertEqual(b.activation['WAYLAND_DISPLAY'], 'wayland-test')
        lifecycle.cleanup_session(b, b.owner)
        self.assertTrue(all(value == '' for value in b.activation.values()))
        self.assertFalse((b.runtime / 'owner.json').exists())

    def test_interrupt_after_spawn_identity_is_published_then_cleaned(self):
        import signal
        b = self.backend
        real = b.identity
        b.ready_on_poll = False
        fired = False
        def interrupted_identity(pid):
            nonlocal fired
            if pid == b.child.pid and not fired:
                fired = True
                signal.raise_signal(signal.SIGTERM)
            return real(pid)
        b.identity = interrupted_identity
        self.assertEqual(lifecycle.start_session(b, b.environment), 1)
        self.assertEqual(b.child.status, -15)
        self.assertFalse((b.runtime / 'owner.json').exists())
        self.assertTrue(any(argv[:3] == ['systemctl', '--user', 'stop'] for argv, _ in b.calls))

    def test_identity_read_failure_still_terminates_owned_unreaped_child(self):
        b = self.backend
        real = b.identity
        b.identity = lambda pid: (_ for _ in ()).throw(OSError('proc unavailable')) if pid == b.child.pid else real(pid)
        b.ready_on_poll = False
        self.assertEqual(lifecycle.start_session(b, b.environment), 1)
        self.assertEqual(b.child.status, -15)
        self.assertFalse((b.runtime / 'owner.json').exists())

    def test_cleanup_marker_cannot_be_overwritten_by_late_readiness(self):
        env = self.ready_record()
        b = self.backend
        b.states['xdg-desktop-portal.service'] = 'active'
        real = b.command
        def mark_failed(argv, env=None, timeout=10):
            result = real(argv, env, timeout)
            if argv[:3] == ['systemctl', '--user', 'restart']:
                record = state.load_session(b.runtime)
                state.save_session(b.runtime, dataclasses.replace(record, phase='failed-cleanup'))
            return result
        b.command = mark_failed
        with self.assertRaises(ValueError): lifecycle.ready_session(b, env)
        self.assertEqual(state.load_session(b.runtime).phase, 'failed-cleanup')

    def test_foreign_change_during_dbus_cleanup_is_not_unset_in_systemd(self):
        env = self.ready_record()
        b = self.backend
        lifecycle.ready_session(b, env)
        real = b.command
        def change_manager(argv, env=None, timeout=10):
            result = real(argv, env, timeout)
            if argv[0] == 'dbus-update-activation-environment' and argv[1] != '--systemd':
                b.manager['DISPLAY'] = ':foreign-new'
            return result
        b.command = change_manager
        lifecycle.cleanup_session(b, b.owner)
        self.assertEqual(b.manager.get('DISPLAY'), ':foreign-new')


class EffectiveUnitTests(unittest.TestCase):
    def setUp(self):
        import shutil
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        home = Path(self.temp.name)
        self.config = home / '.config'
        shutil.copytree(ROOT / 'config/systemd/user', self.config / 'systemd/user')
        self.backend = lifecycle.SystemBackend({'XDG_RUNTIME_DIR': str(home), 'XDG_CONFIG_HOME': str(self.config), 'XDG_SESSION_ID': '4'})
        self.extra_unit = None
        def command(argv, env=None, timeout=10):
            name = argv[3]
            path = self.config / 'systemd/user'
            own = name in ('elephant.service', TARGET)
            fragment = path / name if own else Path('/usr/lib/systemd/user') / name
            drops = [] if own else [str(path / (name+'.d/tab-stack-session.conf'))]
            if self.extra_unit == name: drops.append(str(path / (name+'.d/unreviewed.conf')))
            return subprocess.CompletedProcess(argv, 0, 'LoadState=loaded\nNeedDaemonReload=no\nFragmentPath='+str(fragment)+'\nDropInPaths='+' '.join(drops)+'\nPartOf='+('' if name == TARGET else TARGET)+'\n', '')
        import subprocess
        self.backend.command = command

    def test_reviewed_files_accepted_but_additional_dropins_refused(self):
        self.backend.validate_units()
        for unit in (*UNITS, TARGET):
            self.extra_unit = unit
            with self.subTest(unit=unit), self.assertRaises(ValueError):
                self.backend.validate_units()

    def test_modified_lease_fragment_or_dropin_refused(self):
        for name in ('elephant.service', TARGET, 'xdg-desktop-portal.service.d/tab-stack-session.conf'):
            path = self.config / 'systemd/user' / name
            before = path.read_bytes()
            path.write_bytes(before+b'\n# unreviewed modification\n')
            with self.subTest(name=name), self.assertRaises(ValueError): self.backend.validate_units()
            path.write_bytes(before)

    def test_cached_units_requiring_reload_are_not_accepted(self):
        real = self.backend.command
        def stale(argv, env=None, timeout=10):
            value = real(argv, env, timeout)
            return type(value)(value.args, value.returncode, value.stdout.replace('NeedDaemonReload=no', 'NeedDaemonReload=yes'), value.stderr)
        self.backend.command = stale
        with self.assertRaises(ValueError): self.backend.validate_units()
