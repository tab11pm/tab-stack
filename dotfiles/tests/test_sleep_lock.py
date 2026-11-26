"""No logind inhibitors, screen locking, authentication or sleep in this suite."""
import os
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'config/shojiwm/scripts'))
import sleep_lock as sleep


class Task:
    result = None
    cancelled = False
    def poll(self): return self.result
    def cancel(self): self.cancelled = True


class Backend:
    def __init__(self):
        self.events = []; self.preparing = False; self.maximum = 15.; self.fds = []
        self.context = 'session-A'; self.task = None; self.fail_acquire = False
    def validate(self): return self.context
    def subscribe(self, callback): self.events.append('subscribe'); self.callback = callback
    def properties(self): return self.maximum, self.preparing
    def acquire(self):
        if self.fail_acquire: raise RuntimeError('bus unavailable')
        read, write = os.pipe(); os.close(write); self.fds.append(read)
        self.events.append('acquire'); return read
    def lock(self, deadline, context):
        self.events.append(('lock', deadline, context)); self.task = Task(); return self.task
    def notify(self, ready, text): self.events.append(('notify', ready, text))
    def unsubscribe(self): self.events.append('unsubscribe')


class ControllerTests(unittest.TestCase):
    def setUp(self):
        self.now = 100.; self.backend = Backend()
        self.controller = sleep.SleepController(self.backend, lambda: self.now)
        self.addCleanup(self.controller.stop)
    def start(self): self.controller.start(); return self.backend
    def assertClosed(self, fd):
        with self.assertRaises(OSError): os.fstat(fd)
    def test_subscribe_before_acquire_and_ready_after_ownership(self):
        b = self.start()
        self.assertLess(b.events.index('subscribe'), b.events.index('acquire'))
        self.assertFalse(os.get_inheritable(self.controller.fd))
        self.assertTrue(any(e[:2] == ('notify', True) for e in b.events if isinstance(e, tuple)))
    def test_secure_completion_releases_only_after_confirmed_task(self):
        b = self.start(); fd = self.controller.fd
        self.controller.prepare(True)
        os.fstat(fd)
        self.assertEqual(b.events[-1][0], 'lock')
        self.assertLess(b.events[-1][1], self.now + b.maximum)
        b.task.result = True; self.controller.tick()
        self.assertClosed(fd); self.assertIsNone(self.controller.fd)
    def test_failure_and_timeout_keep_inhibitor_until_resume(self):
        b = self.start(); fd = self.controller.fd
        self.controller.prepare(True); b.task.result = False; self.controller.tick()
        os.fstat(fd); self.assertIn('degraded', self.controller.state)
        self.now += 30; self.controller.tick(); os.fstat(fd)
        self.controller.prepare(False); self.assertIsNotNone(self.controller.fd)
    def test_duplicate_true_does_not_extend_deadline_or_spawn_twice(self):
        b = self.start(); self.controller.prepare(True); original = b.task
        self.now += 2; self.controller.prepare(True)
        self.assertIs(b.task, original)
        self.assertEqual(len([e for e in b.events if isinstance(e, tuple) and e[0] == 'lock']), 1)
    def test_property_roundtrip_consumes_overall_budget(self):
        b = self.start(); original = b.properties
        def slow_properties():
            self.now += 3
            return original()
        b.properties = slow_properties
        self.controller.prepare(True)
        self.assertLessEqual(b.events[-1][1], 114.)
    def test_reentrant_new_signal_during_poll_cannot_release_reacquired_fd(self):
        b = self.start(); self.controller.prepare(True)
        old = b.task
        def poll():
            self.controller.prepare(False)
            return True
        old.poll = poll
        self.controller.tick()
        self.assertIsNotNone(self.controller.fd)
        os.fstat(self.controller.fd)
    def test_resume_cancels_old_task_and_late_success_cannot_release_new_fd(self):
        b = self.start(); self.controller.prepare(True); old = b.task
        self.controller.prepare(False); new = self.controller.fd
        self.assertTrue(old.cancelled)
        old.result = True; self.controller.tick(); os.fstat(new)
    def test_start_during_prepare_processes_current_state(self):
        self.backend.preparing = True; self.start()
        self.assertIsNotNone(self.backend.task)
    def test_expired_task_does_not_release_fd_and_is_cancelled(self):
        b = self.start(); self.controller.prepare(True); fd = self.controller.fd
        self.now += 15; self.controller.tick()
        self.assertTrue(b.task.cancelled); os.fstat(fd)
        self.assertIn('degraded', self.controller.state)
    def test_disconnect_closes_fd_cancels_task_and_reconnect_is_single_subscription(self):
        b = self.start(); self.controller.prepare(True); fd = self.controller.fd; task = b.task
        self.controller.disconnect(); self.assertClosed(fd); self.assertTrue(task.cancelled)
        self.controller.start(); self.assertEqual(b.events.count('unsubscribe'), 1)
        self.assertEqual(b.events.count('subscribe'), 2)
        self.controller.start(); self.assertEqual(b.events.count('subscribe'), 2)
    def test_changed_context_refuses_worker_without_releasing_inhibitor(self):
        b = self.start(); fd = self.controller.fd; b.context = 'session-B'
        self.controller.prepare(True)
        self.assertIsNone(b.task); os.fstat(fd)
        self.assertIn('degraded', self.controller.state)
    def test_reconnect_cannot_adopt_a_different_session(self):
        b = self.start(); self.controller.disconnect(); b.context = 'new-session'
        with self.assertRaises(ValueError): self.controller.start()
    def test_failed_reacquire_is_degraded_not_ready(self):
        b = self.start(); b.fail_acquire = True
        self.controller.prepare(False)
        self.assertIn('degraded', self.controller.state); self.assertIsNone(self.controller.fd)
    def test_zero_or_nonfinite_budget_is_refused(self):
        for value in (0, -1, float('inf'), float('nan')):
            self.backend.maximum = value
            with self.assertRaises(ValueError): self.controller.start()
            self.controller.stop()
    def test_stop_is_idempotent_and_closes_only_own_fd(self):
        self.start(); fd = self.controller.fd
        read, write = os.pipe()
        try:
            self.controller.stop(); self.controller.stop(); self.assertClosed(fd); os.fstat(read)
        finally: os.close(read); os.close(write)


if __name__ == '__main__': unittest.main()
