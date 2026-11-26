#!/usr/bin/env python3
"""Opt-in logind sleep locking. Default check never locks or takes an inhibitor."""
import math
import os
import time


class SleepController:
    """Single-threaded state machine; only a verified task may release its FD."""
    def __init__(self, backend, clock=time.monotonic):
        self.backend = backend
        self.clock = clock
        self.fd = None
        self.task = None
        self.subscribed = False
        self.preparing = False
        self.state = 'stopped'
        self.context = None
        self.deadline = None
        self.epoch = 0

    def _close(self):
        if self.fd is not None:
            os.close(self.fd)
            self.fd = None

    def _cancel(self):
        if self.task is not None:
            task, self.task = self.task, None
            task.cancel()

    def _degraded(self, reason):
        self.state = 'degraded: ' + reason
        self.backend.notify(False, self.state)

    def _acquire(self):
        self._close()
        self.fd = self.backend.acquire()
        os.set_inheritable(self.fd, False)

    def start(self):
        if self.subscribed:
            return
        try:
            context = self.backend.validate()
            if self.context is not None and context != self.context:
                raise ValueError('Cannot adopt a different independent session')
            self.context = context
            self.backend.subscribe(self.prepare)
            self.subscribed = True
            self._acquire()
            maximum, preparing = self.backend.properties()
            if not math.isfinite(maximum) or maximum <= 0:
                raise ValueError('Invalid logind delay budget')
            self.state = 'ready'
            self.backend.notify(True, 'ready: session, subscription and inhibitor verified')
            if preparing:
                self.prepare(True)
        except Exception:
            self.disconnect()
            raise

    def prepare(self, preparing):
        if not self.subscribed:
            return
        if preparing:
            if self.preparing:
                return
            self.preparing = True
            started = self.clock()
            try:
                # Start the overall budget before any potentially slow validation.
                maximum, _ = self.backend.properties()
                if not math.isfinite(maximum) or maximum <= 0:
                    raise ValueError('Invalid delay budget')
                self.deadline = started + maximum - min(1., maximum / 5)
                if self.backend.validate() != self.context:
                    raise ValueError('Session context changed')
                if self.clock() >= self.deadline or self.fd is None:
                    raise ValueError('No usable sleep delay lease')
                self.state = 'locking'
                self.task = self.backend.lock(self.deadline, self.context)
            except Exception:
                self._degraded('lock preparation failed; sleep is not vetoed')
        else:
            self.epoch += 1
            self._cancel()
            self.preparing = False
            try:
                if self.backend.validate() != self.context:
                    raise ValueError('Session context changed')
                self._acquire()
                self.state = 'ready'
                self.backend.notify(True, 'ready: inhibitor reacquired after resume')
            except Exception:
                self.disconnect()
                self._degraded('inhibitor reacquisition failed')

    def tick(self):
        if self.task is None:
            return
        try:
            if self.clock() >= self.deadline:
                self._cancel()
                self._degraded('secure deadline expired; sleep is not vetoed')
                return
            task, epoch = self.task, self.epoch
            result = task.poll()
            if self.task is not task or self.epoch != epoch:
                return
            if result is None:
                return
            self._cancel()
            if result is not True or self.backend.validate() != self.context or self.clock() >= self.deadline:
                self._degraded('secure lock not verified; sleep is not vetoed')
                return
            if self.epoch != epoch:
                return
            self.state = 'secure'
            self._close()
            self.backend.notify(False, 'secure: delay inhibitor released')
        except Exception:
            self._cancel()
            self._degraded('locker verification failed; sleep is not vetoed')

    def disconnect(self):
        self.epoch += 1
        self._cancel()
        self._close()
        self.preparing = False
        self.subscribed = False
        self.backend.unsubscribe()
        self._degraded('system bus or logind unavailable')

    def stop(self):
        self.epoch += 1
        self._cancel()
        self._close()
        if self.subscribed:
            self.backend.unsubscribe()
        self.subscribed = False
        self.preparing = False
        self.state = 'stopped'


def main():
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', nargs='?', choices=('check', 'run'), default='check')
    args = parser.parse_args()
    try:
        from sleep_lock_runtime import preflight, serve
        if args.action == 'check':
            preflight()
            return 0
        return serve()
    except Exception as error:
        # Do not expose D-Bus/subprocess payloads or the desktop environment.
        print('tab-stack sleep lock refused: ' + type(error).__name__, flush=True)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
