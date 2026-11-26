"""Real FD passing and GLib signals on a throwaway private bus, never host logind."""
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time
import unittest


def fixture():
    import dbus
    import dbus.service
    from dbus.mainloop.glib import DBusGMainLoop
    from gi.repository import GLib
    DBusGMainLoop(set_as_default=True)
    bus = dbus.SessionBus(private=True)
    name = dbus.service.BusName('org.freedesktop.login1', bus)
    class Login(dbus.service.Object):
        preparing = False
        pipes = []
        @dbus.service.method('org.freedesktop.DBus.Properties', in_signature='ss', out_signature='v')
        def Get(self, interface, key):
            if key == 'InhibitDelayMaxUSec': return dbus.UInt64(15000000)
            if key == 'PreparingForSleep': return dbus.Boolean(self.preparing)
            raise ValueError('Unexpected fixture property')
        @dbus.service.method('org.freedesktop.login1.Manager', in_signature='ssss', out_signature='h')
        def Inhibit(self, what, who, why, mode):
            assert what == 'sleep' and who == 'tab-stack' and mode == 'delay'
            read, write = os.pipe(); self.pipes.extend((read, write))
            return dbus.types.UnixFd(read)
        @dbus.service.signal('org.freedesktop.login1.Manager', signature='b')
        def PrepareForSleep(self, value): pass
        @dbus.service.method('org.freedesktop.login1.Fixture', in_signature='b', out_signature='')
        def Trigger(self, value):
            self.preparing = bool(value); self.PrepareForSleep(value)
    service = Login(bus, '/org/freedesktop/login1')
    print('READY', flush=True)
    GLib.MainLoop().run()


def probe():
    import dbus
    from dbus.mainloop.glib import DBusGMainLoop
    from gi.repository import GLib
    sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'config/shojiwm/scripts'))
    from sleep_lock_runtime import LogindBackend
    from sleep_lock import SleepController
    # The real adapter's SystemBus is redirected only inside this isolated child.
    address = os.environ['DBUS_SESSION_BUS_ADDRESS']
    os.environ['DBUS_SYSTEM_BUS_ADDRESS'] = address
    DBusGMainLoop(set_as_default=True)
    service = subprocess.Popen([sys.executable, __file__, '--fixture'], stdout=subprocess.PIPE, text=True)
    controller = None
    try:
        assert service.stdout.readline().strip() == 'READY'
        backend = LogindBackend.__new__(LogindBackend)
        backend.bus = None; backend.matches = []; backend.generation = 0
        backend.validate = lambda: 'fixture-session'
        backend.notify = lambda *args: None
        class Task:
            def poll(self): return True
            def cancel(self): pass
        backend.lock = lambda *args: Task()
        controller = SleepController(backend)
        backend.disconnected = controller.disconnect
        controller.start()
        fd = controller.fd; os.fstat(fd)
        assert not os.get_inheritable(fd)
        bus = dbus.SessionBus(private=True)
        interface = dbus.Interface(bus.get_object('org.freedesktop.login1', '/org/freedesktop/login1', introspect=False), 'org.freedesktop.login1.Fixture')
        def until(condition):
            deadline = time.monotonic()+3
            while not condition():
                assert time.monotonic()<deadline, 'Timed out waiting for a private-bus signal'
                while GLib.MainContext.default().pending(): GLib.MainContext.default().iteration(False)
                controller.tick(); time.sleep(.01)
        interface.Trigger(True, timeout=2)
        until(lambda: controller.state == 'secure')
        assert controller.fd is None
        interface.Trigger(False, timeout=2)
        until(lambda: controller.fd is not None)
        os.fstat(controller.fd)
        service.terminate(); service.wait(timeout=3)
        until(lambda: not controller.subscribed)
        assert controller.fd is None
        print('Private D-Bus FD/signal/resume/disconnect: PASS')
        bus.close()
    finally:
        if controller is not None: controller.stop()
        if service.poll() is None: service.terminate(); service.wait(timeout=3)


class BusTests(unittest.TestCase):
    def test_real_fd_and_signals_on_private_bus(self):
        if not shutil.which('dbus-run-session'):
            self.skipTest('dbus-run-session is not installed')
        try:
            import dbus
            from gi.repository import GLib
        except ImportError:
            self.skipTest('Optional python-dbus/python-gobject are not installed')
        result = subprocess.run(['dbus-run-session', '--', sys.executable, __file__, '--probe'],
                                text=True, capture_output=True, timeout=15)
        if result.returncode and 'Operation not permitted' in result.stderr and 'Failed to bind socket' in result.stderr:
            self.skipTest('Sandbox forbids private D-Bus socket bind; run this test outside sandbox')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('Private D-Bus FD/signal/resume/disconnect: PASS', result.stdout)


if __name__ == '__main__':
    if sys.argv[1:] == ['--fixture']: fixture()
    elif sys.argv[1:] == ['--probe']: probe()
    else: unittest.main()
