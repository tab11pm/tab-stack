from dataclasses import replace
import hashlib
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'config/shojiwm/scripts'))
import session_lifecycle as lifecycle
import session_state as state
from session_fixtures import Backend, TARGET, UNITS

SLEEP = 'tab-stack-sleep-lock.service'


class OptionalBackend(Backend):
    def __init__(self, runtime):
        super().__init__(runtime); self.states[SLEEP] = 'inactive'
    def session_units(self): return (*UNITS, SLEEP)
    def command(self, argv, env=None, timeout=10):
        result = super().command(argv, env, timeout)
        if argv[:3] == ['systemctl','--user','start'] and TARGET in argv:
            self.states[SLEEP] = 'failed' if self.fail_unit == SLEEP else 'active'
        return result


class OptionalSessionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.addCleanup(self.temp.cleanup)
        self.backend = OptionalBackend(self.temp.name)
    def prepare(self):
        b=self.backend; state.prepare_runtime(b.runtime)
        state.save_session(b.runtime, state.SessionRecord(b.owner,b.child_identity,'starting',(*UNITS,SLEEP)))
        return {**b.environment,'TAB_STACK_SESSION_TOKEN':b.owner.token}
    def test_optional_ready_check_and_logout_own_all_six_services(self):
        b=self.backend; env=self.prepare(); lifecycle.ready_session(b,env)
        lifecycle.check_session(b,env)
        lifecycle.cleanup_session(b,b.owner)
        self.assertTrue(all(value=='inactive' for value in b.states.values()))
        self.assertIn(SLEEP,next(argv for argv,_ in b.calls if argv[:3]==['systemctl','--user','stop']))
    def test_notify_failure_prevents_false_session_readiness(self):
        b=self.backend; b.fail_unit=SLEEP; env=self.prepare()
        with self.assertRaises(ValueError): lifecycle.ready_session(b,env)
        self.assertFalse(state.read_private_json(b.runtime/'ready.json')['ready'])
    def test_ready_reentry_refuses_changed_lease(self):
        b=self.backend; env=self.prepare(); lifecycle.ready_session(b,env)
        record=state.load_session(b.runtime)
        state.save_session(b.runtime,replace(record,services=UNITS))
        with self.assertRaises(ValueError): lifecycle.ready_session(b,env)
    def test_preexisting_monitor_blocks_takeover(self):
        self.backend.states[SLEEP]='active'
        with self.assertRaises(ValueError): lifecycle.start_session(self.backend,self.backend.environment)
        self.assertEqual(self.backend.calls,[])
    def test_optin_provenance_requires_exact_regular_file(self):
        config=Path(self.temp.name)/'config'; path=config/'systemd/user/tab-stack-session.target.d/sleep-lock.conf'
        backend=lifecycle.SystemBackend({'XDG_RUNTIME_DIR':self.temp.name,'XDG_CONFIG_HOME':str(config)})
        self.assertEqual(lifecycle.managed_services(backend),UNITS)
        path.parent.mkdir(parents=True); path.write_text('unknown')
        with self.assertRaises(ValueError): lifecycle.managed_services(backend)
        path.write_bytes((ROOT/'optional/sleep-lock/sleep-lock.conf').read_bytes()); path.chmod(0o644)
        self.assertEqual(lifecycle.managed_services(backend),(*UNITS,SLEEP))
        path.unlink(); path.symlink_to(ROOT/'optional/sleep-lock/sleep-lock.conf')
        with self.assertRaises(ValueError): lifecycle.managed_services(backend)
    def test_optional_unit_hashes_pin_the_shipped_contract(self):
        for name, digest in lifecycle.SLEEP_FILE_DIGESTS.items():
            source=ROOT/'optional/sleep-lock'/Path(name).name
            self.assertEqual(hashlib.sha256(source.read_bytes()).hexdigest(),digest)
        unit=(ROOT/'optional/sleep-lock/tab-stack-sleep-lock.service').read_text()
        self.assertIn('Type=notify',unit); self.assertIn('PartOf=tab-stack-session.target',unit)
        self.assertNotIn('[Install]',unit); self.assertNotIn('KillMode=process',unit)
    def test_degraded_status_is_not_reported_as_healthy_service(self):
        backend=lifecycle.SystemBackend.__new__(lifecycle.SystemBackend)
        outputs=iter(['active','degraded: inhibitor unavailable'])
        backend.command=lambda *a:subprocess.CompletedProcess(a[0],0,next(outputs),'')
        self.assertEqual(backend.unit_states((SLEEP,)),{SLEEP:'failed'})


if __name__ == '__main__': unittest.main()
