#!/usr/bin/env python3
"""Start the independent Shoji locker, or inspect/preview it without locking."""
import argparse
import fcntl
import json
import math
import os
from pathlib import Path
import shutil
import stat
import subprocess
import sys
import time
from urllib.parse import unquote, urlparse


SOURCE = Path(__file__).resolve().parent
PAM_DIRECTORY = Path("/etc/pam.d")
# Same binary as start-shell: the shell module needs the notification-policy patch.
_PATCHED = Path(os.environ.get("XDG_DATA_HOME") or Path.home() / ".local/share") / "shoji-shell/quickshell/bin/quickshell"
QUICKSHELL = os.environ.get("SHOJI_QUICKSHELL") or (str(_PATCHED) if os.access(_PATCHED, os.X_OK) else "quickshell")


def private_runtime():
    runtime = Path(os.environ.get("XDG_RUNTIME_DIR", ""))
    if not runtime.is_absolute() or runtime.stat().st_uid != os.getuid():
        raise RuntimeError("Нет доступного каталога текущей сессии XDG_RUNTIME_DIR.")
    directory = runtime / "shoji-lock"
    directory.mkdir(mode=0o700, exist_ok=True)
    info = directory.lstat()
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid():
        raise RuntimeError("Некорректный каталог shoji-lock.")
    directory.chmod(0o700)
    return directory


def pam_configuration(runtime):
    # Use only our service. A missing system file selects the bundled policy,
    # never another locker's policy or login's session/TTY policy.
    if (PAM_DIRECTORY / "shoji-lock").is_file():
        return str(PAM_DIRECTORY), "shoji-lock"
    policy = PAM_DIRECTORY
    if not all((policy / name).is_file() for name in ("system-auth", "system-local-login")):
        raise RuntimeError("Нужен системный PAM-сервис /etc/pam.d/shoji-lock для этой ОС.")
    directory = runtime / "pam"
    directory.mkdir(mode=0o700, exist_ok=True)
    # pam_start_confdir resolves includes in its own directory. Keep includes
    # linked to the installed system policy, including transitive includes.
    for source in policy.iterdir():
        target = directory / source.name
        if source.is_file() and source.name != "shoji-lock" and not target.is_symlink() and not target.exists():
            target.symlink_to(source)
    shutil.copyfile(SOURCE / "pam/shoji-lock", directory / "shoji-lock")
    (directory / "shoji-lock").chmod(0o600)
    return str(directory), "shoji-lock"


def file_uri(value):
    if not isinstance(value, str):
        return None
    parsed = urlparse(value)
    if parsed.scheme not in ("", "file"):
        return None
    path = Path(unquote(parsed.path) if parsed.scheme == "file" else value)
    return path.as_uri() if path.is_absolute() and path.is_file() else None


def read_json(name):
    try:
        return json.loads((SOURCE.parent / name).read_text())
    except (OSError, ValueError):
        return {}


def background_url():
    fallback = (SOURCE.parent / "assets/default-wallpaper.svg").as_uri()
    try:
        outputs = read_json("wallpapers.json").get("outputs", {})
        primary = os.environ.get("SHOJI_PRIMARY_OUTPUT", "")
        for value in [outputs.get(primary), *outputs.values()]:
            if uri := file_uri(value):
                return uri
    except AttributeError:
        pass
    return fallback


def lock_backgrounds():
    """Per-output lock wallpapers: the drawer's choice, else that output's desktop still."""
    result = {}
    try:
        desktop = read_json("wallpapers.json").get("outputs", {})
        chosen = read_json("system-settings.json").get("lockWallpapers") or {}
        for name in {*desktop, *chosen}:
            if uri := file_uri(chosen.get(name)) or file_uri(desktop.get(name)):
                result[name] = uri
    except AttributeError:
        pass
    return result


def remaining(deadline, maximum):
    if deadline is None:
        return maximum
    value = min(maximum, deadline - time.monotonic())
    if value <= 0:
        raise RuntimeError('Locker deadline expired')
    return value


def check(environment, deadline=None):
    checked_env = dict(environment, WAYLAND_DEBUG="1")
    result = subprocess.run(
        [QUICKSHELL, "--path", str(SOURCE.parent / "lock-check.qml"), "--no-color"],
        env=checked_env, capture_output=True, text=True, timeout=remaining(deadline, 10),
    )
    output = result.stdout + result.stderr
    if result.returncode or "SHOJI_LOCK_CHECK_OK" not in output:
        # No authentication takes place here; diagnostics contain no password.
        errors = [line for line in output.splitlines() if "ERROR" in line or "WARN" in line]
        raise RuntimeError("Не загрузились компоненты блокировки. " + " ".join(errors[-4:]))
    if "ext_session_lock_manager_v1" not in output:
        raise RuntimeError("Текущий композитор не объявляет протокол блокировки Wayland.")


def status(deadline=None):
    try:
        result = subprocess.run(
            [QUICKSHELL, "ipc", "--path", str(SOURCE.parent / "lock.qml"), "call", "session", "status"],
            capture_output=True, text=True, timeout=remaining(deadline, 1),
        )
        if result.returncode == 0:
            value = json.loads(result.stdout)
            return value if isinstance(value, dict) else None
    except (ValueError, subprocess.TimeoutExpired):
        pass
    return None


def start(environment, runtime, deadline=None):
    # Serialise launchers, not the locker. The detached process survives a panel
    # reload; --no-duplicate also protects launches outside this helper.
    with (runtime / "launch.lock").open("a") as launch_lock:
        if deadline is None:
            fcntl.flock(launch_lock, fcntl.LOCK_EX)
        else:
            while True:
                remaining(deadline, 1)
                try:
                    fcntl.flock(launch_lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                    break
                except BlockingIOError:
                    time.sleep(remaining(deadline, .02))
        existing = status(deadline)
        if existing and existing.get("secure"):
            return
        check(environment, deadline)
        remaining(deadline, 1)
        log_path = runtime / "locker.log"
        descriptor = os.open(log_path, os.O_WRONLY | os.O_CREAT | os.O_APPEND | os.O_NOFOLLOW, 0o600)
        with os.fdopen(descriptor, "a") as log:
            process = subprocess.Popen(
                [QUICKSHELL, "--no-duplicate", "--path", str(SOURCE.parent / "lock.qml"), "--no-color"],
                env=environment, stdin=subprocess.DEVNULL, stdout=log, stderr=log,
                start_new_session=True, close_fds=True,
            )
        secure_deadline = min(deadline or float('inf'), time.monotonic() + 7)
        while time.monotonic() < secure_deadline:
            current = status(secure_deadline)
            if current and current.get("secure"):
                return
            if process.poll() is not None:
                raise RuntimeError("Процесс блокировки завершился. См. " + str(log_path))
            time.sleep(min(.1, max(0, secure_deadline - time.monotonic())))
        # Never kill a possibly secure lock: a conformant compositor keeps a
        # failed client's session locked, which needs recovery from another TTY.
        raise RuntimeError("Нет подтверждения блокировки. См. " + str(log_path))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--check", action="store_true", help="Check QML, PAM policy and compositor; do not lock")
    mode.add_argument("--preview", action="store_true", help="Open a non-locking preview window")
    parser.add_argument('--deadline', type=float, help='Absolute monotonic deadline for supervised sleep locking')
    args = parser.parse_args()
    if args.deadline is not None:
        if not math.isfinite(args.deadline) or args.preview or args.check:
            parser.error('--deadline requires a finite value and ordinary lock mode')
        remaining(args.deadline, 1)
    environment = dict(os.environ, SHOJI_LOCK_BACKGROUND=background_url(),
                       SHOJI_LOCK_BACKGROUNDS=json.dumps(lock_backgrounds()))
    if args.preview:
        return subprocess.call([QUICKSHELL, "--path", str(SOURCE.parent / "lock-preview.qml")], env=environment)
    runtime = private_runtime()
    directory, service = pam_configuration(runtime)
    environment.update(SHOJI_LOCK_PAM_DIRECTORY=directory, SHOJI_LOCK_PAM_SERVICE=service)
    if args.check:
        check(environment)
        print(f"OK: QML loads; ext-session-lock-v1 available; PAM policy {directory}/{service}.")
        print("Password authentication and actual locking were not attempted.")
        return 0
    start(environment, runtime, args.deadline)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, RuntimeError, subprocess.SubprocessError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
