#!/usr/bin/env python3
"""Private, local PC activity intervals. Newline JSON over stdin/stdout."""
import argparse
from datetime import date, datetime, time as datetime_time, timedelta, timezone
import fcntl
import json
import math
import os
from pathlib import Path
import sqlite3
import subprocess
import sys
import time
from zoneinfo import ZoneInfo


def system_timezone():
    try:
        return str(Path('/etc/localtime').resolve()).split('/zoneinfo/', 1)[1]
    except (OSError, IndexError):
        return 'UTC'


def probe_lock(shell_path):
    lock_path = str(Path(shell_path) / 'lock.qml')
    try:
        result = subprocess.run(['quickshell','ipc','--path',lock_path,'call','session','status'],
                                capture_output=True,text=True,timeout=1)
        if result.returncode == 0:
            data = json.loads(result.stdout)
            if type(data.get('locked')) is bool and type(data.get('secure')) is bool:
                return dict(known=True,locked=data['locked'] or data['secure'])
    except (OSError,ValueError,subprocess.TimeoutExpired):
        pass
    # Distinguish no locker from an unresponsive locker without printing argv.
    for process in Path('/proc').iterdir():
        if not process.name.isdigit(): continue
        try:
            if process.stat().st_uid != os.getuid(): continue
            argv=(process/'cmdline').read_bytes().split(b'\0')
            if os.fsencode(lock_path) in argv:
                return dict(known=False,locked=True)
        except (OSError,ProcessLookupError):
            continue
    return dict(known=True,locked=False)


class ActivityStore:
    def __init__(self, path):
        self.path = Path(path)
        self.path.parent.mkdir(parents=True, mode=0o700, exist_ok=True)
        self.path.parent.chmod(0o700)
        self.lease = open(str(self.path) + '.lock', 'a')
        os.chmod(self.lease.name, 0o600)
        try:
            fcntl.flock(self.lease, fcntl.LOCK_EX | fcntl.LOCK_NB)
            self.db = sqlite3.connect(self.path)
            self.path.chmod(0o600)
            self.db.executescript('''
                CREATE TABLE IF NOT EXISTS intervals (
                    start REAL NOT NULL, end REAL NOT NULL, app_id TEXT);
                CREATE INDEX IF NOT EXISTS intervals_end ON intervals(end);
                CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT);
            ''')
        except Exception:
            if hasattr(self, 'db'): self.db.close()
            self.lease.close()
            raise

    def close(self):
        self.db.close()
        self.lease.close()

    def get_paused(self):
        row = self.db.execute("SELECT value FROM settings WHERE key='manual_paused'").fetchone()
        return bool(row and row[0] == 'true')

    def set_paused(self, paused):
        with self.db:
            self.db.execute("INSERT OR REPLACE INTO settings VALUES ('manual_paused', ?)",
                            ('true' if paused else 'false',))

    def record_interval(self, start, end, app_id):
        if not all(math.isfinite(v) for v in (start, end)) or end < start:
            raise ValueError('Invalid interval')
        if end == start: return
        with self.db:
            last = self.db.execute('SELECT rowid, end, app_id FROM intervals ORDER BY rowid DESC LIMIT 1').fetchone()
            if last and abs(last[1] - start) < 0.001 and last[2] == app_id:
                self.db.execute('UPDATE intervals SET end=? WHERE rowid=?', (end, last[0]))
            else:
                self.db.execute('INSERT INTO intervals VALUES (?,?,?)', (start,end,app_id))

    def summary(self, selected, period, zone):
        day = date.fromisoformat(selected)
        if period not in ('day','week'): raise ValueError('Invalid period')
        tz = ZoneInfo(zone or system_timezone())
        if period == 'week': day -= timedelta(days=day.weekday())
        days = 7 if period == 'week' else 1
        def midnight(d): return datetime.combine(d, datetime_time(), tz).timestamp()
        lo, hi = midnight(day), midnight(day+timedelta(days=days))
        rows = self.db.execute('SELECT start,end,app_id FROM intervals WHERE end>? AND start<?',(lo,hi)).fetchall()
        bars = [{'label': ['Пн','Вт','Ср','Чт','Пт','Сб','Вс'][i] if days==7 else f'{i:02d}',
                 'seconds':0.0} for i in range(7 if days==7 else 24)]
        if days==7:
            boundaries = [midnight(day+timedelta(days=i)) for i in range(8)]
        else:
            # Both folds retain the repeated autumn hour; nonexistent spring
            # hours collapse to valid UTC boundaries instead of losing time.
            boundaries = sorted({lo,hi} | {
                datetime.combine(day,datetime_time(hour=hour),tz).replace(fold=fold).timestamp()
                for hour in range(24) for fold in (0,1)})
            boundaries = [v for v in boundaries if lo <= v <= hi]
        total, apps = 0.0, {}
        for start,end,app_id in rows:
            start,end=max(lo,start),min(hi,end)
            seconds=end-start
            total += seconds
            if app_id: apps[app_id]=apps.get(app_id,0)+seconds
            for a,b in zip(boundaries,boundaries[1:]):
                overlap=max(0,min(end,b)-max(start,a))
                index=(datetime.fromtimestamp(a,tz).date()-day).days if days==7 else datetime.fromtimestamp(a,tz).hour
                bars[index]['seconds'] += overlap
        ranking=sorted(apps.items(),key=lambda pair:(-pair[1],pair[0]))[:5]
        return dict(date=selected, period=period, periodStart=day.isoformat(),
                    totalSeconds=total, averageSeconds=total/7 if days==7 else total,
                    bars=bars, apps=[dict(appId=app,seconds=seconds,share=seconds/total if total else 0)
                                    for app,seconds in ranking])


class Tracker:
    def __init__(self, store):
        self.store=store
        self.manual_paused=store.get_paused()
        self.viewing=False
        self.state=dict(connected=False,idle=False,locked=True,appId=None)
        self.last=None
        self.selected=date.today().isoformat()
        self.period='day'
        self.zone=system_timezone()

    @property
    def allowed(self):
        return self.state['connected'] and not (self.manual_paused or self.state['locked'] or (self.state['idle'] and not self.viewing))

    def update(self, state, wall, monotonic):
        if self.last:
            old_wall,old_mono,allowed,app=self.last
            elapsed=monotonic-old_mono
            if allowed and 0<elapsed<=3 and abs(wall-old_wall-elapsed)<1:
                self.store.record_interval(old_wall,old_wall+elapsed,app)
        self.state=dict(state)
        self.last=(wall,monotonic,self.allowed,self.state.get('appId'))

    def toggle(self):
        self.manual_paused=not self.manual_paused
        self.store.set_paused(self.manual_paused)
        if self.last:
            wall,mono,_,app=self.last
            self.last=(wall,mono,self.allowed,app)

    def command(self, cmd, wall, mono):
        if not isinstance(cmd,dict): raise ValueError('Expected object')
        op=cmd.get('op')
        if op=='state':
            for key in ('connected','idle','locked'):
                if type(cmd.get(key)) is not bool: raise ValueError('Invalid state')
            app=cmd.get('appId')
            if app is not None and (not isinstance(app,str) or len(app)>512): raise ValueError('Invalid appId')
            state={key:cmd[key] for key in ('connected','idle','locked')}
            state['appId']=app or None
            self.update(state,wall,mono)
        elif op=='toggle':
            self.update(self.state,wall,mono)
            self.toggle()
        elif op=='viewing':
            if type(cmd.get('enabled')) is not bool: raise ValueError('Invalid viewing mode')
            self.update(self.state,wall,mono)
            self.viewing=cmd['enabled']
            self.last=(wall,mono,self.allowed,self.state.get('appId'))
        elif op=='lock':
            if type(cmd.get('locked')) is not bool: raise ValueError('Invalid lock state')
            self.update(dict(self.state,locked=cmd['locked']),wall,mono)
        elif op=='query':
            selected,period,zone=cmd.get('date'),cmd.get('period'),cmd.get('timezone') or system_timezone()
            self.store.summary(selected,period,zone)  # validate before changing selection
            self.selected,self.period,self.zone=selected,period,zone
        else: raise ValueError('Unknown operation')
        return self.snapshot()

    def snapshot(self):
        status=('Агент работает / Я отошёл' if self.manual_paused else
                'Нет связи с ShojiWM' if not self.state['connected'] else
                'Экран заблокирован' if self.state['locked'] else
                'Просмотр · время учитывается' if self.viewing else
                'Автопауза · 5 минут без действий' if self.state['idle'] else 'Я за ПК')
        return dict(self.store.summary(self.selected,self.period,self.zone),ready=True,
                    manualPaused=self.manual_paused,viewing=self.viewing,status=status,error='',tracking=self.allowed)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--self-check',action='store_true')
    parser.add_argument('--database',type=Path)
    parser.add_argument('--lock-status',action='store_true')
    args=parser.parse_args()
    if args.self_check:
        import subprocess
        return subprocess.call([sys.executable,str(Path(__file__).with_name('test-activity-tracker.py'))])
    if os.environ.get('SHOJI_ENABLE_ACTIVITY') != '1':
        print('Activity accounting is disabled; opt in locally first', file=sys.stderr)
        return 1
    if args.lock_status:
        print(json.dumps(probe_lock(Path(__file__).resolve().parent)),flush=True)
        return 0
    os.umask(0o077)
    path=args.database or Path(os.environ.get('XDG_STATE_HOME',str(Path.home()/'.local/state')))/'shoji-shell/activity.sqlite3'
    try:
        store=ActivityStore(path)
    except (OSError,sqlite3.Error):
        print(json.dumps(dict(ready=False,error='Не удалось открыть историю времени. База не изменена.'),ensure_ascii=False),flush=True)
        return 1
    tracker=Tracker(store)
    print(json.dumps(tracker.snapshot(),ensure_ascii=False),flush=True)
    try:
        for line in sys.stdin:
            try:
                result=tracker.command(json.loads(line),time.time(),time.monotonic())
            except (ValueError,TypeError,KeyError,sqlite3.Error,OSError):
                result=dict(ready=False,error='Не удалось прочитать команду или сохранить статистику.')
            print(json.dumps(result,ensure_ascii=False),flush=True)
    finally:
        store.close()
    return 0

if __name__=='__main__': sys.exit(main())
