"""Collector consent checks in disposable state directories; no desktop IPC."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / 'config/shoji-shell/activity-tracker.py'

class ActivityConsentTests(unittest.TestCase):
    def test_disabled_collector_does_not_create_history(self):
        for flag in (None, '0'):
            with self.subTest(flag=flag), tempfile.TemporaryDirectory() as directory:
                path = Path(directory) / 'history.sqlite3'
                environment = dict(os.environ)
                environment.pop('SHOJI_ENABLE_ACTIVITY', None)
                if flag is not None:
                    environment['SHOJI_ENABLE_ACTIVITY'] = flag
                result = subprocess.run([sys.executable, '-B', str(SCRIPT), '--database', str(path)],
                    env=environment, input='', text=True, capture_output=True, timeout=5)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(path.exists(), 'Disabled collector created private history')

    def test_enabled_collector_initializes_in_isolated_database(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'history.sqlite3'
            result = subprocess.run([sys.executable, '-B', str(SCRIPT), '--database', str(path)],
                env=dict(os.environ, SHOJI_ENABLE_ACTIVITY='1'), input='', text=True,
                capture_output=True, timeout=5)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue(path.is_file())

if __name__ == '__main__':
    unittest.main()
