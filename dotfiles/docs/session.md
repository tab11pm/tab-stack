# Independent tab-stack session

This opt-in session runs ShojiWM on Wayland. An X11 SDDM greeter is independent
of the desktop protocol. Choose **tab-stack** for the managed session; the
existing ShojiWM entry remains available for recovery. Do not change another
user's autologin, PAM, suspend/lock policy, boot configuration, or packages.

The wrapper owns one compositor child and `tab-stack-session.target`.
The target owns Elephant and the main/GTK/WLR/ShojiWM portal services.
ShojiWM continues to supervise the panel and polkit agent. Configuration reload
is not logout. No `graphical-session.target` or Omarchy target is started by this
wrapper; audio, keyring, default.target and other users' managers are outside
its lease. One live graphical login per UID is supported. Another live login,
unknown closing login, active legacy service, unexpected unit provenance or
unresolved marker stops startup. Verified completed independent logouts have the
narrow exception described under guarded recovery.

`tab-stack-session check` reads the active session's private readiness lease and
verifies the wrapper/compositor identities, logind login, Wayland socket peer,
unit provenance, selected manager environment and service states. It requires no
registration token or compositor ancestry from the caller: terminals started
through launcher systemd scopes and TTY can inspect status. `ready` still requires
the compositor's token, ancestry and display environment and grants no equivalent
permission to arbitrary status callers.

## Prepare and verify the source

Use an isolated checkout. Never copy its whole configuration over an installed
profile. Keep personal integration files outside this tree.

```bash
python3 -m unittest discover -s dotfiles/tests -p 'test_session_*.py' -v
/usr/lib/qt6/bin/qmllint -I dotfiles/config/shoji-shell dotfiles/config/shoji-shell/HomeSystemCard.qml
tsc --noEmit -p dotfiles/config/shojiwm/tsconfig.json
SYSTEMD_UNIT_PATH="$PWD/dotfiles/config/systemd/user:/usr/lib/systemd/user" \
  systemd-analyze --user verify dotfiles/config/systemd/user/tab-stack-session.target \
  dotfiles/config/systemd/user/elephant.service
```

Use the installed TypeScript compiler and pinned `shoji_wm` runtime imports.
Do not use an implicit `npx` download. A skipped Unix socket test or inaccessible
user bus is a pending host check, not a pass. Qt's linter may report the existing
Quickshell `QProcess::ExitStatus` type dependency and unused QtQuick.Layouts import;
compare before/after diagnostics in the same component directory.

Stage installation in a temporary home first:

```bash
stage=$(mktemp -d)
python3 dotfiles/scripts/install.py --component session --target-home "$stage"
python3 dotfiles/scripts/install.py --component session --target-home "$stage" --apply
```

The default installer component list is unchanged. Session installation copies
only two runtime modules, the terminal launcher, its Python user-site
bootstrap, the target, Elephant unit and four portal drop-ins. It makes no service calls. Run it separately from directory components.
Neither a desktop template nor a system login entry is installed by it.
Before host writes, review the whole source diff independently.

## First migration prerequisites

First confirm recovery through an existing login entry and a working TTY login.
An administrator in another account can install the one system entry; the desktop
account does not need sudo. Keep work saved before operator logout.

After leaving the legacy graphical session, log into a TTY as the desktop user.
Inspect `loginctl list-sessions`, then `loginctl show-session ID` with only
User/Type/Class/State/Leader. There must be no remaining graphical login for that
UID. Other users' logins can remain. Do not stop services from another user's
manager. Inspect the fragments and drop-ins of the five services:

```bash
systemctl --user show elephant.service xdg-desktop-portal.service \
  xdg-desktop-portal-gtk.service xdg-desktop-portal-wlr.service \
  xdg-desktop-portal-shojiwm.service -p FragmentPath -p DropInPaths -p ActiveState
```

Proceed only after reviewing their provenance. Unknown units/drop-ins stop the
migration. Runtime verifies exact hashes of owned user fragments/drop-ins and
rejects any additional drop-in, including packaged overrides, until a separate
source review defines a supported policy. Cached units requiring daemon-reload
are refused. Once the old graphical login has ended, the operator can stop these
known legacy services in the desktop user's own manager:

```bash
systemctl --user stop elephant.service xdg-desktop-portal.service \
  xdg-desktop-portal-gtk.service xdg-desktop-portal-wlr.service \
  xdg-desktop-portal-shojiwm.service
```

This first stop is explicit. The new wrapper will refuse to take over already
active services. Do not disable Omarchy sleep services or start the old graphical
session targets to make a test pass.

## User files and exact backup

Preview both operations. The migration recognizes a single known startup command
and native logout hook; unknown or duplicated forms refuse before any write.
It preserves monitor code and unrelated QML styling.

```bash
python3 dotfiles/scripts/install.py --component session
python3 dotfiles/scripts/migrate-session.py
```

If an existing session file differs, review its bytes and SHA256 separately.
Pass `--expect-existing '/absolute/path=REVIEWED_SHA256'` to the session installer
only for the exact reviewed file. Do not derive and approve a checksum blindly
in one command. Existing symlinks and symlink ancestors are refused.

After prerequisites and review, apply the separately previewed commands:

```bash
python3 dotfiles/scripts/install.py --component session --apply
python3 dotfiles/scripts/migrate-session.py --apply
systemctl --user daemon-reload
```

Keep both printed manifest paths. Each transaction records presence/absence,
mode, numeric uid/gid, original checksum, backup checksum and installed checksum.
Backup directories are 700; original copies and manifests are 600. The source
and installed files may differ outside the two migration hooks. The renderer
writes a private entry under `$XDG_STATE_HOME/tab-stack/session/tab-stack.desktop`
(or `~/.local/state/...`), with a fixed `Exec=/usr/bin/python3 -P -m tab_stack_session start`. The bootstrap
resolves the logged-in user's home and XDG configuration at runtime.
It does not widen home permissions, restart services or start the target.

Inspect the fixed rendered Exec command and availability of its user-site
bootstrap, terminal launcher and runtime helpers. Python user-site imports must
be enabled. After changing the system Python major/minor version or PYTHONUSERBASE,
preview/reinstall the session component into that interpreter's new user site.
Run `desktop-file-validate` on the rendered entry: this installed validator rejects
`DesktopNames` as an extension. Record exactly that diagnostic and verify a
scratch copy with only `DesktopNames=ShojiWM` removed; all standardized fields
and the fixed Exec must validate. Keep DesktopNames in the actual SDDM entry.
The fixed command works with the installed SDDM 0.21 script's `exec $@` parsing;
quoted executable paths do not. The source execution test uses a harmless helper
with this exact consumer behavior, including homes with spaces, Unicode, quotes,
backslashes, dollars, backticks and percent signs. No shell evaluation is used.
The renderer rejects an input executable path containing `=` or a line break.

## Administrative entry installation

Administrative destination is exactly
`/usr/local/share/wayland-sessions/tab-stack.desktop`, root:root 644.
Install only the checked rendered entry after the user prerequisites and fresh
backup. This is a separate operator action; no user installer calls sudo.

Before writing, inspect the destination and every ancestor with lstat; refuse
symlinks. Require the destination absent, or review its exact existing bytes,
mode, ownership and SHA256 first. Preserve a root-private backup and manifest
covering presence/absence, original metadata/checksum and installed checksum.
Read the private rendered source as root without changing home permissions,
compare its reviewed SHA256, write a temporary regular file with root:root 644,
and atomically rename it. Recheck bytes/mode/owner afterwards. Retain the legacy
packaged entry and the backup. No SDDM restart, logout or autologin change is
part of the file installation. A concrete host recipe must be prepared and
reviewed against the current destination before this operation.

## Application and acceptance

In an agreed window, use the checked native logout helper, then choose tab-stack
in the existing greeter. A failed new login can return to ShojiWM or the TTY.
Source checks do not establish cold-boot, graphical, or clean-user acceptance.
Never invoke logout merely to perform source validation.

Inside the new session, check its read-only status and user units:

```bash
~/.local/bin/tab-stack-session check
systemctl --user show tab-stack-session.target elephant.service \
  xdg-desktop-portal.service xdg-desktop-portal-gtk.service \
  xdg-desktop-portal-wlr.service xdg-desktop-portal-shojiwm.service \
  -p Id -p ActiveState -p SubState
systemctl --user show graphical-session.target graphical-session-pre.target \
  omarchy-sleep-lock.service -p Id -p ActiveState
```

Read only the five selected manager environment keys, never publish a full
environment dump. Confirm one panel, one polkit agent, one Elephant, working
launcher and file picker. Their display must belong to this compositor. Reload
TSX and verify that the target remains active and no process duplicates appear.
Panel crash/recovery and locker behavior need separate safe scenarios.

After native logout, from TTY confirm the target and five services inactive;
audio/keyring and the manager still work, selected dead display values are
invalidated, and no ownership failure marker remains. Log in again and repeat.
Cold boot and a clean-user installation are separate acceptance checks. Source
or fixture results never stand in for these host observations.

## Guarded recovery

A completed independent logout writes private `completed.json` receipts in the
runtime directory. logind may keep that logged-out session in `closing` while
background applications finish. Re-entry accepts only those closing session IDs
whose cleanup succeeded in this boot and whose recorded wrapper and compositor
identities are no longer running. Receipts for IDs that logind has removed are
pruned at the next successful cleanup. Active sessions, unknown closing sessions,
live old compositors and failed-cleanup markers still block re-entry. A legacy
ShojiWM logout produces no independent cleanup receipt.

Return to the preserved legacy entry or TTY. Before rollback, ensure the new
compositor is gone and no graphical login of that UID is still using its lease.
Stop only known owned session services in that user's manager, inspect selected
environment and invalidate verified dead display values separately in systemd
and D-Bus activation. Do not kill processes by name, stop the user manager,
restore a dead display, or start Omarchy targets.

An unresolved `failed-cleanup` or stale marker deliberately blocks re-entry.
Inspect its recorded PID, UID, process start ticks, boot ID, session ID and
unit provenance first; a PID alone proves nothing. Preserve the marker privately
while investigating. Remove only verified stale metadata after compositor/service
and display cleanup. There is no automatic stale-owner takeover command.

Restore the system entry from its root-private manifest only when installed
checksum, regular-file type and root:root 644 still match. Originally absent
means remove only that matching added entry. A later edit stops rollback.

Roll back user migration first, then session installation, with their exact
private manifests:

```bash
python3 dotfiles/scripts/migrate-session.py --rollback /absolute/private/migration/manifest.json
python3 dotfiles/scripts/migrate-session.py --rollback /absolute/private/session-install/manifest.json
systemctl --user daemon-reload
```

The tool validates every installed checksum and backup before restoring any
file. It refuses later edits or symlinks and rechecks each file immediately before
restoring it. Concurrent conflicts remain untouched with a recovery-required
manifest; do not retry blindly. Previous files regain their recorded
mode; originally absent files are removed. Keep backups until relogin, logout,
recovery and remaining greeter acceptance have been recorded.
