#!/usr/bin/env python3
import importlib.util
from pathlib import Path
import tempfile
import unittest
from datetime import datetime, timezone

spec = importlib.util.spec_from_file_location('activity_tracker', Path(__file__).with_name('activity-tracker.py'))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

def stamp(value):
    return datetime.fromisoformat(value).replace(tzinfo=timezone.utc).timestamp()

class ActivityTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.store = module.ActivityStore(Path(self.tmp.name) / 'state' / 'activity.sqlite3')
        self.tracker = module.Tracker(self.store)
        self.start = stamp('2026-10-12T10:00:00')
        self.state = dict(connected=True, idle=False, locked=False, appId='editor')
    def tearDown(self):
        self.store.close()
        self.tmp.cleanup()
    def update(self, seconds, **changes):
        self.state.update(changes)
        self.tracker.update(self.state, self.start + seconds, seconds)
    def total(self):
        return self.store.summary('2026-10-12', 'day', 'UTC')['totalSeconds']
    def test_manual_pause_persists_and_input_does_not_resume(self):
        self.update(0); self.update(1)
        self.tracker.toggle()
        self.update(2, idle=True); self.update(3, idle=False)
        self.assertEqual(self.total(), 1)
        self.assertTrue(module.Tracker(self.store).manual_paused)
        self.tracker.command({'op':'toggle'}, self.start+4, 4); self.update(5)
        self.assertEqual(self.total(), 2)
    def test_auto_pause_at_300_and_input_resumes(self):
        for second in range(300): self.update(second)
        self.update(300, idle=True); self.update(301)
        self.assertEqual(self.total(), 300)
        self.update(302, idle=False); self.update(303)
        self.assertEqual(self.total(), 301)
    def set_viewing(self, seconds, enabled):
        return self.tracker.command({'op':'viewing','enabled':enabled},self.start+seconds,seconds)
    def test_viewing_counts_idle_time_without_backfilling(self):
        self.update(0, idle=True)
        self.set_viewing(1,True)
        self.update(2)
        self.assertEqual(self.total(),1)
        self.assertTrue(self.tracker.snapshot()['viewing'])
        self.assertEqual(self.tracker.snapshot()['status'],'Просмотр · время учитывается')
    def test_viewing_off_restores_existing_idle_pause(self):
        self.update(0,idle=True);self.set_viewing(1,True);self.update(2)
        self.set_viewing(3,False);self.update(4)
        self.assertEqual(self.total(),2)
        self.assertFalse(self.tracker.allowed)
        self.update(5,idle=False);self.update(6)
        self.assertEqual(self.total(),3)
    def test_manual_pause_overrides_viewing(self):
        self.update(0,idle=True);self.set_viewing(1,True);self.update(2)
        self.tracker.command({'op':'toggle'},self.start+3,3)
        self.update(4,idle=False);self.update(5,idle=True)
        self.assertEqual(self.total(),2)
        self.assertFalse(self.tracker.allowed)
        self.assertTrue(self.tracker.snapshot()['viewing'])
        self.tracker.command({'op':'toggle'},self.start+6,6);self.update(7)
        self.assertEqual(self.total(),3)
    def test_lock_and_disconnect_override_viewing(self):
        self.update(0,idle=True);self.set_viewing(1,True);self.update(2,locked=True);self.update(3)
        self.update(4,locked=False,connected=False);self.update(5)
        self.update(6,connected=True);self.update(7)
        self.assertEqual(self.total(),2)
    def test_viewing_resets_after_restart(self):
        self.set_viewing(0,True)
        self.assertFalse(module.Tracker(self.store).viewing)
    def test_viewing_command_rejects_non_boolean(self):
        for enabled in ['false',0,None]:
            with self.assertRaises(ValueError): self.set_viewing(0,enabled)
        self.assertFalse(self.tracker.viewing)
    def test_sleep_gap_not_counted_in_viewing(self):
        self.update(0,idle=True);self.set_viewing(1,True);self.update(2)
        self.update(1000);self.update(1001)
        self.assertEqual(self.total(),2)
    def test_focus_app_and_no_app(self):
        self.update(0); self.update(1, appId='browser'); self.update(2, appId=None); self.update(3)
        report = self.store.summary('2026-10-12','day','UTC')
        self.assertEqual(report['totalSeconds'], 3)
        self.assertEqual({a['appId']: a['seconds'] for a in report['apps']}, {'editor':1,'browser':1})
    def test_connection_loss_and_lock(self):
        self.update(0); self.update(1, connected=False); self.update(2)
        self.update(3, connected=True, locked=True); self.update(4)
        self.update(5, locked=False); self.update(6)
        self.assertEqual(self.total(), 2)
    def test_long_gap_and_clock_jump_are_not_charged(self):
        self.update(0); self.update(1); self.update(1000)
        self.tracker.update(self.state, self.start+5000, 1001)
        self.tracker.update(self.state, self.start+5001, 1002)
        self.assertEqual(self.total(), 2)
    def test_restart_does_not_recover_downtime(self):
        self.update(0); self.update(1)
        module.Tracker(self.store).update(self.state, self.start+3600, 3600)
        self.assertEqual(self.total(), 1)
    def test_midnight_and_week_split(self):
        self.store.record_interval(stamp('2026-10-11T23:59:00'),stamp('2026-10-12T00:01:00'),'editor')
        for day in ['2026-10-11','2026-10-12']:
            self.assertEqual(self.store.summary(day,'day','UTC')['totalSeconds'],60)
            self.assertEqual(self.store.summary(day,'week','UTC')['totalSeconds'],60)
    def test_top_five_and_week_average(self):
        for i in range(7): self.store.record_interval(self.start+i*20,self.start+i*20+i+1,str(i))
        report=self.store.summary('2026-10-12','week','UTC')
        self.assertEqual([a['appId'] for a in report['apps']],['6','5','4','3','2'])
        self.assertEqual(report['averageSeconds'],4)
        self.assertEqual(len(report['bars']),7)
    def test_timezone(self):
        self.store.record_interval(stamp('2026-10-11T20:00:00'),stamp('2026-10-11T20:01:00'),'editor')
        report=self.store.summary('2026-10-12','day','Asia/Krasnoyarsk')
        self.assertEqual(report['totalSeconds'],60)
        self.assertEqual(report['bars'][3]['seconds'],60)
    def test_dst_repeated_hour(self):
        self.store.record_interval(stamp('2026-11-01T05:00:00'),stamp('2026-11-01T07:00:00'),'editor')
        report=self.store.summary('2026-11-01','day','America/New_York')
        self.assertEqual(report['bars'][1]['seconds'],7200)
        self.assertEqual(sum(b['seconds'] for b in report['bars']),7200)
    def test_empty_and_permissions(self):
        report=self.store.summary('2026-10-12','day','UTC')
        self.assertEqual(report['apps'],[])
        self.assertEqual(len(report['bars']),24)
        self.assertEqual(self.store.path.stat().st_mode & 0o777,0o600)
    def test_invalid_interval(self):
        with self.assertRaises(ValueError): self.store.record_interval(self.start,self.start-1,'editor')
        with self.assertRaises(ValueError): self.store.record_interval(self.start,float('nan'),'editor')
    def test_bad_query(self):
        for args in [('bad','day','UTC'),('2026-10-12','year','UTC'),('2026-10-12','day','BAD')]:
            with self.assertRaises((ValueError,KeyError)): self.store.summary(*args)
    def test_corrupt_database_is_preserved(self):
        broken=Path(self.tmp.name)/'broken.sqlite3'; broken.write_bytes(b'not a database')
        with self.assertRaises(Exception): module.ActivityStore(broken)
        self.assertEqual(broken.read_bytes(),b'not a database')
    def test_exclusive_collector(self):
        with self.assertRaises(BlockingIOError): module.ActivityStore(self.store.path)
    def test_lock_probe_without_session(self):
        result=module.probe_lock(Path(self.tmp.name)/'shell')
        self.assertEqual(result, {'known':True,'locked':False})
    def test_bad_commands_do_not_mutate_state(self):
        for cmd in [{'op':'state','idle':'false'}, {'op':'state','appId':['bad']}, {'op':'lock','locked':'false'}, {'op':'unknown'}]:
            with self.assertRaises(ValueError): self.tracker.command(cmd,self.start,0)
        self.assertFalse(self.tracker.manual_paused)

if __name__=='__main__': unittest.main()
