# Independent sleep lock implementation plan

> **For agentic workers:** Use superpowers:executing-plans task by task.

**Goal:** An opt-in session-owned logind monitor using the existing Shoji locker.

**Architecture:** A small testable inhibitor controller, a dbus-python/GLib adapter,
and an asynchronous locker task. Type=notify readiness follows verified session,
subscription and inhibitor acquisition. An independent transient scope keeps the
locker outside the monitor's kill cgroup. No host installation in this execution.

**Tech stack:** Python stdlib, dbus-python, PyGObject, systemd user units.

**Spec:** ../specs/2026-11-03-independent-sleep-lock-design.md (approved 2026-11-03).

## Global constraints

- Do not interrupt the desktop, invoke live lock/sleep or install host files.
- Preserve selected five session services, ownership checks and bounded cleanup.
- Delay is not a veto; failed secure must not be reported as cancelled sleep.
- Never kill the detached locker; no password or unlock IPC.
- Installation is explicit, preview-only by default, with guarded transaction rollback.

## Review focus

- A late worker from a previous sleep/reconnect must not release a new inhibitor.
- A locker with matching PID but different start identity must be refused.
- Restart/disconnect while preparing must not create FD leaks or duplicate workers.
- Stopping the monitor must leave a secure locker outside its control group.
- Session component reinstall must not silently enable the optional sleep service.

## Task 1: Bounded existing launcher

Files: `dotfiles/config/shoji-shell/lock/{launch.py,test_launch.py,SessionLock.qml}`.
Interface: optional `--deadline` monotonic absolute float; thread remaining budget
through flock, IPC, QML check and secure wait. Status includes process PID.

- [x] RED tests for expired deadline, contended flock, total IPC/QML budget and malformed status.
- [x] Implement deadline without changing manual invocation timing or killing locker.
- [x] Run launcher suite, retain existing behavior checks.

## Task 2: Controller and real adapter

Files: `dotfiles/config/shojiwm/scripts/sleep_lock.py`, `dotfiles/tests/test_sleep_lock.py`.
Interfaces: `SleepController(backend, clock)`, start/prepare/tick/disconnect/stop;
backend acquire/properties/subscribe/task/notify. CLI `check` is read-only, `run`
owns the inhibitor. SystemBackend + lease metadata validate the same compositor.

- [x] RED controller tests for secure/release, failure/timeout, duplicates, resume,
  owner change, subscribe ordering, reconnection and late callbacks.
- [x] Implement controller and fd-safe GLib adapter; run only fixture-backed run paths.
- [x] Test real socket notification and fd ownership in isolation, and command/identity guards.

## Task 3: Optional units and guarded installer

Files: `dotfiles/optional/sleep-lock/*`, `dotfiles/scripts/{install.py,sleep_lock_install.py}`,
`dotfiles/config/shojiwm/scripts/session_lifecycle.py`, optional integration tests.
Interfaces: `--component sleep-lock` installs only reviewed runtime/locker/unit delta;
`--rollback MANIFEST` uses existing transaction guards; no service calls.
Explicit exact-hash target drop-in selects sixth service in the session lease.

- [x] RED isolated install tests for preview, exact paths, preservation, rollback and symlink refusal.
- [x] RED lifecycle tests for optional ready/start/cleanup/failure and unreviewed drop-in refusal.
- [x] Implement exact-hash opt-in and Type=notify unit, preserving legacy session installation.
- [x] Run both existing session suite and new sleep suite; offline systemd verify.

## Task 4: Documentation, review and handoff

Files: sleep-lock operator guide, session/install docs, dependency list and status.

- [x] Document source/staging checks, reviewed checksums, apply and guarded rollback;
  live lock/sleep remain pending a separate window.
- [x] Run privacy, whitespace, QML, Python suites and read-only host preflight.
- [x] Review whole change in a fresh context and fix material issues with RED→GREEN tests.
- [x] Leave reviewable source in isolated worktree; no deployment or package changes.

## Execution record

Native execution authorized by “ок начни работу”. Existing root and old session
worktree have unrelated changes and are preserved. A managed worktree was created;
edits are prepared in sandbox scratch, then copied there as scoped reviewed files.

Validation: 99 full-discovery tests and 12 launcher tests passed, no skips;
QML/offline units/read-only preflight passed. Private D-Bus and harmless native
scope boundaries verified. Independent review found no Critical/Important issues.
Documentation status updates complete the planned final documentation task.
Host application remains pending; no deployment has been authorized here.
