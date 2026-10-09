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

SDDM reads `/usr/lib/sddm/sddm.conf.d/*.conf`, then
`/etc/sddm.conf.d/*.conf`, sorted by filename within each directory, and finally
`/etc/sddm.conf`. The last file has the highest priority. A `zz-` filename alone
does not guarantee success. See [sddm.conf(5)](https://man.archlinux.org/man/sddm.conf.5.en).

From the administrative account enter `sudo -i` for a host root shell, then set
the source path. Substitute the absolute path recorded by the desktop user:

```bash
greeter_source='/absolute/path/to/tab-stack/dotfiles/system/sddm/zz-tab-stack-greeter.conf'
```

Run this read-only preview in that shell. It validates the source bytes and
simulates replacement of the destination at its actual position in the local
directory. Only `General.DisplayServer` and its originating file are printed.
For **installed-state verification**, run the same block with `python3 -`
instead of `python3 - "$greeter_source"` (no candidate argument).

```bash
python3 - "$greeter_source" <<'PY'
import configparser
from pathlib import Path
import sys

candidate = Path(sys.argv[1]) if len(sys.argv) == 2 else None
expected = b"[General]\nDisplayServer=x11\n"
if candidate is not None and candidate.read_bytes() != expected:
    raise SystemExit("STOP: unexpected candidate content")
local = Path("/etc/sddm.conf.d")
destination = local / "zz-tab-stack-greeter.conf"
locations = sorted(Path("/usr/lib/sddm/sddm.conf.d").glob("*.conf"))
local_files = set(local.glob("*.conf"))
if candidate is not None:
    local_files.add(destination)
locations += sorted(local_files)
main = Path("/etc/sddm.conf")
if main.exists() or main.is_symlink():
    locations.append(main)
value, origin = "x11", "SDDM default"
for location in locations:
    if location.is_symlink():
        raise SystemExit("STOP: config symlink requires target backup and separate review")
    content = (candidate.read_text() if candidate is not None and location == destination
               else location.read_text())
    parser = configparser.ConfigParser(interpolation=None, strict=False,
                                       delimiters=("=",))
    parser.optionxform = str
    parser.read_string(content)
    if parser.has_option("General", "DisplayServer"):
        value = parser.get("General", "DisplayServer").strip()
        origin = str(location)
print(f"General.DisplayServer={value}; origin={origin}")
if value != "x11":
    raise SystemExit("STOP: X11 is overridden; investigate before installation/application")
PY
```

Stop on any read/parse error; this procedure is for conventional SDDM INI
files. Investigate unusual Qt INI syntax separately. Config symlinks require
separate review and fresh target backups before proceeding.
Do not delete or rewrite a conflicting file to force this preview to pass.

On the audited machine, preview on 2026-10-10 yielded
`General.DisplayServer=x11` from `/etc/sddm.conf.d/zz-tab-stack-greeter.conf`.
This is a proposed value, not evidence of installation or a running X11 greeter.

## Fresh backup and installation

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
    if test -e "$greeter_destination"; then test -f "$greeter_destination"; fi
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
