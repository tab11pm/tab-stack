# Independent SDDM greeter

This optional **system** configuration makes SDDM's shared login screen use
X11. ShojiWM remains a Wayland desktop. Existing session entries, themes and
autologin settings remain in their own files. The user installer does not
install anything from `system/`; this procedure is separate.

The source is [zz-tab-stack-greeter.conf](../system/sddm/zz-tab-stack-greeter.conf).
Do not remove Hyprland or Omarchy during this step. Existing Wayland greeter
commands remain available for recovery. A different account may still use an
Omarchy/Hyprland desktop, including through autologin.

## Before installation

The desktop user records the absolute source path with `realpath` from the
checkout. The existing administrative account performs the following system
operations in a normal host terminal. Do not add desktop-user sudo rights or
change permissions on a private home or backup directory.

Confirm that login through a TTY works and that `sudo -v` succeeds from the
administrative account. Read `systemctl is-active sddm.service` and inspect
active sessions locally with `loginctl list-sessions`; do not publish account
names or session logs. Confirm `/usr/bin/Xorg` exists and the old greeter
command is still available. Save work and agree on an application window that
accounts for other users **before changing the configuration**: another
automatic SDDM start or reboot can pick up a written file. Installation itself
does not restart SDDM.

The selected-file preparation snapshot is supplementary. It contains no package
archives or boot recovery image. Its `source_uid_visible_to_sandbox` and similar
fields are not host ownership values to use with `chown`. Make a fresh host
backup below, even if that earlier snapshot passed its checksum checks.

## Preview configuration priority

SDDM 0.21 reads all non-hidden files selected by Qt's `QDir::Files` from
`/usr/lib/sddm/sddm.conf.d`, then `/etc/sddm.conf.d`, with Qt locale-aware
sorting, and finally `/etc/sddm.conf`. This includes files such as
`zzz-local.conf.bak`, not only `*.conf`. The last location has the highest
priority. A `zz-` filename alone does not guarantee success. See the
[pinned SDDM loader](https://github.com/sddm/sddm/blob/v0.21.0/src/common/ConfigReader.cpp#L128-L205)
and [sddm.conf(5)](https://man.archlinux.org/man/sddm.conf.5.en).

From the administrative account enter `sudo -i` for a host root shell, then set
the source path. Substitute the absolute path recorded by the desktop user:

```bash
greeter_source='/absolute/path/to/tab-stack/dotfiles/system/sddm/zz-tab-stack-greeter.conf'
```

Build this temporary Qt ordering tool in the root shell. It uses the same
Qt API as SDDM, adding the proposed filename in a private mirror for preview.
It requires the installed Qt6Core development files, `pkg-config` and `c++`;
if unavailable, stop rather than approximate ordering or install new packages.
The tool and mirror are disposable, private preparation artifacts.

```bash
greeter_tools=$(mktemp -d /root/tab-stack-greeter-tools-XXXXXXXX)
cat > "$greeter_tools/order.cpp" <<'CPP'
#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QTemporaryDir>
#include <QTextStream>
int main(int argc, char **argv) {
    QCoreApplication app(argc, argv);
    if (argc < 2 || argc > 3) return 1;
    const auto filter = QDir::Files | QDir::NoDotAndDotDot;
    QStringList names = QDir(QString::fromLocal8Bit(argv[1])).entryList(filter, QDir::NoSort);
    if (argc == 3 && !names.contains(QString::fromLocal8Bit(argv[2])))
        names.append(QString::fromLocal8Bit(argv[2]));
    QTemporaryDir mirror;
    if (!mirror.isValid()) return 1;
    for (const QString &name : names) {
        if (name.contains('\n') || name.contains('\r') || name.contains('/')) return 1;
        QFile file(mirror.filePath(name));
        if (!file.open(QIODevice::WriteOnly)) return 1;
    }
    QTextStream out(stdout);
    for (const QString &name : QDir(mirror.path()).entryList(filter, QDir::LocaleAware))
        out << name << '\n';
    return 0;
}
CPP
c++ -std=c++17 -fPIC "$greeter_tools/order.cpp" -o "$greeter_tools/order" $(pkg-config --cflags --libs Qt6Core)
export GREETER_ORDER_TOOL="$greeter_tools/order"
```

Run this read-only preview in that shell. It validates the source bytes and
simulates replacement of the destination at its actual position in the local
directory. Only `General.DisplayServer` and its originating file are printed.
For **installed-state verification**, run the same block with `python3 -`
instead of `python3 - "$greeter_source"` (no candidate argument).

```bash
python3 - "$greeter_source" <<'PY'
from pathlib import Path
import os
import subprocess
import sys

candidate = Path(sys.argv[1]) if len(sys.argv) == 2 else None
expected = b"[General]\nDisplayServer=x11\n"
if candidate is not None and candidate.read_bytes() != expected:
    raise SystemExit("STOP: unexpected candidate content")
# Match the running daemon's locale rather than this terminal's locale.
# BEGIN HOST LOCALE
pid = subprocess.check_output(["systemctl", "show", "sddm.service", "-p", "MainPID", "--value"], text=True).strip()
if not pid.isdecimal() or int(pid) == 0:
    raise SystemExit("STOP: running SDDM locale is unavailable")
locale_keys = {b"LANG", b"LANGUAGE", b"LC_ALL", b"LC_COLLATE", b"LC_CTYPE",
               b"LC_MESSAGES", b"LC_TIME", b"LC_NUMERIC", b"LC_MONETARY"}
daemon_env = {b"PATH": b"/usr/bin:/bin"}
for entry in Path(f"/proc/{pid}/environ").read_bytes().split(b"\0"):
    key, separator, val = entry.partition(b"=")
    if separator and key in locale_keys:
        daemon_env[key] = val
# END HOST LOCALE
order_tool = os.environ["GREETER_ORDER_TOOL"]
def ordered(directory, virtual=None):
    args = [order_tool, str(directory)]
    if virtual is not None:
        args.append(virtual)
    result = subprocess.check_output(args, env=daemon_env, text=True)
    return [directory / name for name in result.splitlines()]
local = Path("/etc/sddm.conf.d")
destination = local / "zz-tab-stack-greeter.conf"
locations = ordered(Path("/usr/lib/sddm/sddm.conf.d"))
locations += ordered(local, destination.name if candidate is not None else None)
main = Path("/etc/sddm.conf")
if main.exists() or main.is_symlink():
    locations.append(main)
value, origin = "x11", "SDDM default"
for location in locations:
    if location.is_symlink():
        raise SystemExit("STOP: config symlink requires target backup and separate review")
    content = (candidate.read_text() if candidate is not None and location == destination
               else location.read_text())
    section = "General"
    for raw_line in content.splitlines():
        line = raw_line.strip().split("#", 1)[0].strip()
        if "=" in line:
            key, val = line.split("=", 1)
            if section == "General" and key.strip() == "DisplayServer":
                value, origin = val.strip(), str(location)
        elif line.startswith("[") and line.endswith("]"):
            section = line[1:-1]
if value not in {"x11", "x11-user", "wayland"}:
    raise SystemExit("STOP: unsupported DisplayServer value")
print(f"General.DisplayServer={value}; origin={origin}")
if value != "x11":
    raise SystemExit("STOP: X11 is overridden; investigate before installation/application")
PY
```

Stop on any read/tool error. The key reader follows SDDM 0.21 line parsing,
including implicit General, repeated keys/sections and `#` comments. Config symlinks require
separate review and fresh target backups before proceeding.
Do not delete or rewrite a conflicting file to force this preview to pass.

The initial alphabetical preview was superseded after review of SDDM source.
A Qt-based fixture check passes; host preview must still pass with the running
daemon locale. This is not evidence of installation or a running X11 greeter.

## Fresh backup and installation

Before replacing an **existing** destination, inspect it locally with
`stat`, `pacman -Qo` and a text viewer. Do not publish its contents. If its
origin is unknown, or it contains any theme, autologin, session command or other
settings beyond the selected greeter backend, stop: replacing it would discard
those settings. Arrange a separate, scoped migration first. Once an ordinary
backend-only file is understood and its replacement explicitly approved,
record its SHA-256 as `greeter_reviewed_sha256` in this root shell. Bind review
to that digest; do not compute and approve an unknown file automatically.
For an absent destination this variable is unnecessary.

Continue in the same host root shell only after the prerequisites and preview
passed. This block stops on a symlink or non-regular destination and requires
an existing ordinary local configuration directory. It makes a new private,
root-owned backup on each run. Keep the printed backup path for TTY recovery.

```bash
(
    set -eu
    test "$(id -u)" -eq 0
    umask 077
    greeter_destination=/etc/sddm.conf.d/zz-tab-stack-greeter.conf
    test -d /etc/sddm.conf.d && test ! -L /etc/sddm.conf.d
    test ! -L "$greeter_destination"
    if test -e "$greeter_destination"; then
        test -f "$greeter_destination"
        test -n "${greeter_reviewed_sha256:-}"
        test "$(sha256sum -- "$greeter_destination" | cut -d ' ' -f 1)" = "$greeter_reviewed_sha256"
    fi
    test -f "$greeter_source"
    greeter_backup=$(mktemp -d /root/tab-stack-greeter-XXXXXXXX)
    printf 'Recovery directory: %s\n' "$greeter_backup"
    cp -- "$greeter_source" "$greeter_backup/candidate.conf"
    python3 - "$greeter_backup/candidate.conf" <<'PY'
from pathlib import Path
import sys
assert Path(sys.argv[1]).read_bytes() == b"[General]\nDisplayServer=x11\n", "unexpected candidate"
PY
    cp -a -- /etc/sddm.conf.d "$greeter_backup/local-configs"
    cp -a -- /usr/lib/sddm/sddm.conf.d "$greeter_backup/packaged-configs"
    if test -e /etc/sddm.conf || test -L /etc/sddm.conf; then
        cp -a -- /etc/sddm.conf "$greeter_backup/main.conf"
    fi
    if test -e "$greeter_destination"; then
        cp -a -- "$greeter_destination" "$greeter_backup/previous.conf"
        stat -c '%a %u %g' -- "$greeter_destination" > "$greeter_backup/previous.metadata"
        sha256sum -- "$greeter_backup/previous.conf" | cut -d ' ' -f 1 > "$greeter_backup/previous.sha256"
        printf 'present\n' > "$greeter_backup/original-state"
    else
        printf 'absent\n' > "$greeter_backup/original-state"
    fi
    sha256sum -- "$greeter_backup/candidate.conf" | cut -d ' ' -f 1 > "$greeter_backup/installed.sha256"
    if test "$(cat "$greeter_backup/original-state")" = present; then
        test "$(cat "$greeter_backup/previous.sha256")" = "$greeter_reviewed_sha256"
        test "$(sha256sum -- "$greeter_destination" | cut -d ' ' -f 1)" = "$greeter_reviewed_sha256"
    else
        test ! -e "$greeter_destination" && test ! -L "$greeter_destination"
    fi
    # Install the validated root-owned snapshot, avoiding a source-change race.
    install -o root -g root -m 644 -- "$greeter_backup/candidate.conf" "$greeter_destination"
    cmp -- "$greeter_backup/candidate.conf" "$greeter_destination"
    cmp -- "$greeter_source" "$greeter_destination"
    test "$(stat -c '%a %u %g' -- "$greeter_destination")" = '644 0 0'
    printf 'File installed and compared. Re-run installed-state priority verification.\n'
)
```

`sudo install -o root -g root -m 644 -- SOURCE DESTINATION` is the equivalent
operation from the administrative account outside the root shell. Here SOURCE
is the validated, root-owned candidate copy. Only the destination is written
under `/etc`; backup files stay private under `/root`.

If the block fails, stop and inspect its printed backup directory and the
current destination. If it reached the install command, the new file may
already be present; do not rerun blindly. Re-run the priority reader **without
a candidate**. If it fails or shows a conflict, do not apply the change; use
the checked rollback below. Preserve the backup until live acceptance finishes.

No competing administrator should edit SDDM files during this procedure. The
shell checks are not a lock against concurrent root operations. Symlinks in
the other config locations are archived as links by `cp -a`; investigate them
and independently preserve their targets before proceeding if any are present.

## Apply and accept separately

After installation/verification, leave the root shell with `exit`. Application
requires the separately agreed logout/reboot window and saved work. Do not
restart the display manager from an active desktop as part of installation.
This guide intentionally contains no automatic restart command.

Check the shared login screen, input and displays. Manually choose the existing
ShojiWM session; inside it verify `printf '%s\n' "$XDG_SESSION_TYPE"` reports
`wayland`, the compositor/display belongs to ShojiWM, and the panel is not
duplicated. Confirm the SDDM greeter uses Xorg through host service/process
inspection; an intentionally active Hyprland desktop in another account does
not imply failure. Check logout/relogin and a cold boot. Keep autologin behaviour
for other accounts intact. Record each result in the
[acceptance matrix](../../docs/migration/acceptance.md).

If the greeter works but ShojiWM fails to start, investigate session entry,
environment and logs. Do not switch the desktop to X11 or replace a profile.

## Checked, single-file rollback

From the verified TTY administrative account, enter `sudo -i`. Set the exact
backup directory printed during installation. Never choose a backup by guessing
which directory is newest. The current destination must still match the saved
installed checksum; otherwise stop and investigate later edits.

```bash
greeter_backup='/root/tab-stack-greeter-XXXXXXXX'
(
    set -eu
    test "$(id -u)" -eq 0
    greeter_destination=/etc/sddm.conf.d/zz-tab-stack-greeter.conf
    test -d "$greeter_backup" && test ! -L "$greeter_backup"
    test "$(stat -c '%a %u %g' -- "$greeter_backup")" = '700 0 0'
    test -d /etc/sddm.conf.d && test ! -L /etc/sddm.conf.d
    test -f "$greeter_destination" && test ! -L "$greeter_destination"
    test "$(sha256sum -- "$greeter_destination" | cut -d ' ' -f 1)" = "$(cat "$greeter_backup/installed.sha256")"
    case "$(cat "$greeter_backup/original-state")" in
        absent)
            rm -- "$greeter_destination"
            test ! -e "$greeter_destination"
            ;;
        present)
            test -f "$greeter_backup/previous.conf" && test ! -L "$greeter_backup/previous.conf"
            test "$(sha256sum -- "$greeter_backup/previous.conf" | cut -d ' ' -f 1)" = "$(cat "$greeter_backup/previous.sha256")"
            test "$(stat -c '%a %u %g' -- "$greeter_backup/previous.conf")" = "$(cat "$greeter_backup/previous.metadata")"
            cp -a --remove-destination -- "$greeter_backup/previous.conf" "$greeter_destination"
            cmp -- "$greeter_backup/previous.conf" "$greeter_destination"
            test "$(stat -c '%a %u %g' -- "$greeter_destination")" = "$(cat "$greeter_backup/previous.metadata")"
            ;;
        *) printf 'STOP: unknown original state\n' >&2; exit 1 ;;
    esac
    printf 'Single-file rollback verified. No service was restarted.\n'
)
```

Re-run installed-state priority verification to see the restored origin/value;
`wayland` can be the expected old value, so the reader's X11 assertion will
then stop. Apply the restored configuration only in an agreed recovery window.
Do not restore whole directories, touch PAM or remove packages. This rollback
has been documented and statically reviewed; live TTY execution remains an
acceptance task. See also [recovery boundaries](../../docs/migration/recovery.md).
