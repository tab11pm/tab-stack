# Lock before system sleep

The optional `tab-stack-sleep-lock.service` watches logind for sleep requests and
uses the existing Shoji locker. It belongs to `tab-stack-session.target`, not the
panel or legacy graphical targets. Default installation does not enable it.
Automatic idle sleep remains a separate opt-in setting.

Source implementation and staging tests are available. Live password, suspend,
resume and cold-boot acceptance remain pending. An active service does not prove
that the screen was locked during an actual sleep.

## Behavior and limits

The monitor subscribes to `PrepareForSleep`, acquires a `sleep` delay inhibitor
and reports readiness after verifying its session and subscription. On a request
it starts one launcher in an independent transient user scope. That scope keeps
the detached locker alive when the monitor is stopped or restarted; normal
cgroup cleanup of the monitor must never kill the locker.

One monotonic deadline covers flock contention, IPC, QML validation and secure
wait. Success is followed by read-only IPC and process verification: locked and
secure, stable PID/start identity, current UID, exact QML path and the same
Wayland display. There is no password or unlock IPC. A late task cannot release
a newly acquired inhibitor.

Only verified secure releases the delay early. Failure retains the FD and
reports degraded. **A delay inhibitor cannot veto sleep after its timeout.**
logind may proceed even if locking failed; that is not cancelled suspend.
Privileged inhibitor bypass is outside this mechanism. The actual budget is
read from logind; no global policy is changed.

After resume the monitor acquires a new inhibitor without unlocking. Bus/logind
loss cancels only its launcher, closes its own FD and triggers bounded reconnect.
A different session cannot be adopted on reconnect. Failure diagnostics remain
in the journal; no passwords or full environment are logged.

## Prerequisites and source checks

Use the [independent session](session.md) and
[independent locker](../config/shoji-shell/lock/README.md). Optional Arch packages
are listed in [`sleep-lock-arch.txt`](../dependencies/sleep-lock-arch.txt):
`python-dbus` and `python-gobject`. systemd-run, user services and system bus must
already work. The check below reads installed session/PAM files and logind
properties. It does not acquire an inhibitor or launch QML.

```bash
python3 -m unittest discover -s dotfiles/tests -p 'test_sleep_lock*.py' -v
python3 -m unittest discover -s dotfiles/tests -p 'test_session_*.py' -v
python3 dotfiles/config/shoji-shell/lock/test_launch.py
/usr/lib/qt6/bin/qmllint -I dotfiles/config/shoji-shell dotfiles/config/shoji-shell/lock/SessionLock.qml
python3 dotfiles/config/shojiwm/scripts/sleep_lock.py check
```

The private-bus test uses fixture logind on a throwaway dbus-run-session bus.
Its SystemBus address is redirected only in that subprocess; no host inhibitor,
locker or suspend is called. A sandbox socket skip is not a pass: run that test
outside sandbox before claiming FD/signal integration. Missing optional Python
packages likewise leave that check pending.

## Stage before installation

Use a temporary home outside the checkout. Stage the base session and shell,
after meeting the shader/plugin prerequisites in [installation](install.md).
Do not copy an installed profile or personal settings into source.

```bash
stage=$(mktemp -d)
python3 dotfiles/scripts/install.py --component session --target-home "$stage" --apply
python3 dotfiles/scripts/install.py --component shoji-shell --target-home "$stage" --apply
python3 dotfiles/scripts/install.py --component sleep-lock --target-home "$stage"
python3 dotfiles/scripts/install.py --component sleep-lock --target-home "$stage" --apply
```

The optional transaction writes exactly seven files:

- `shojiwm/scripts/session_lifecycle.py`, `sleep_lock.py`, `sleep_lock_runtime.py`;
- `shoji-shell/lock/launch.py` and `shoji-shell/lock/SessionLock.qml`;
- `systemd/user/tab-stack-sleep-lock.service`;
- `systemd/user/tab-stack-session.target.d/sleep-lock.conf`.

It requires a matching installed base session and known locker support files.
It makes no service calls and does not touch profile JSON, PAM, SDDM, other users,
kernel or packages. Optional units live under `optional/` in source, so a default
or session component installation alone cannot enable them.

## Prepare exact host application

Preview from the source checkout:

```bash
python3 dotfiles/scripts/install.py --component sleep-lock
```

Existing differing files require explicit `--expect-existing PATH=SHA256`.
Read and review their complete diff first; never compute and approve an unknown
checksum blindly. Launcher and SessionLock are copied as reviewed files, not
merged. For local customizations, port the small deadline/status changes
separately or explicitly review replacement. Unknown supporting files, units,
drop-ins and symlinks stop installation.

**Apply only after leaving the graphical session in a separately agreed window.**
The new target drop-in changes the lease from five to six services; installing
it during the current five-service session would break ownership checks. Confirm
TTY recovery, end the session, inspect that its target and owned services stopped,
then install the reviewed delta. Keep the private manifest. A future operator
recipe must bind exact current baselines and checksums before any host write.

After installation, perform user daemon-reload and enter the independent session.
Its target starts the monitor. Do not enable it in default.target, start the old
graphical targets or change global logind policy. Do not disable legacy sleep
services merely to make tests pass.

## Readiness and live acceptance

```bash
~/.local/bin/tab-stack-session check
systemctl --user show tab-stack-sleep-lock.service -p ActiveState -p StatusText
systemd-inhibit --list --no-pager
```

StatusText distinguishes ready/secure from degraded. Session check rejects
degraded or missing monitor readiness even if its PID is active. Inspect failure
journals locally; do not publish private logs.

In the agreed window, verify wrong/correct passwords on the current PAM policy,
manual suspend/resume, existing panel idle sleep, repeated sleep, monitor
reconnect and applicable hardware. The desktop must stay covered until normal
authentication. Panel restart must leave monitor and secure locker intact.
Deliberate locker failure needs a tested TTY recovery path. Do not run these
tests during ordinary work.

## Guarded rollback

After ending the graphical session, use the exact manifest printed by the
optional transaction, not a guessed newest backup:

```bash
python3 dotfiles/scripts/install.py --rollback /absolute/private/manifest.json
```

Targets, modes, owners and checksums are checked before restoration. Later edits
or symlinks cause refusal. Inspect restored files and perform user daemon-reload
before next login. Rollback removes only this opt-in and restores its exact
prior files; an active secure locker is never a recovery target. It does not
promise to restart the Omarchy monitor, which was already inactive at baseline.

API references: [logind](https://www.freedesktop.org/software/systemd/man/latest/org.freedesktop.login1.html),
[inhibitors](https://systemd.io/INHIBITOR_LOCKS/),
[dbus-python GLib](https://dbus.freedesktop.org/doc/dbus-python/dbus.mainloop.html),
[systemd cgroup cleanup](https://www.freedesktop.org/software/systemd/man/latest/systemd.kill.html).
