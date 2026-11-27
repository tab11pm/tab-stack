#!/usr/bin/env python3
"""Помощник виджета колонки.

  kolonka-widget.py status [ip]      — одна JSON-строка: состояние колонки и плеера
  kolonka-widget.py ctl ip action [arg] — команда плееру/голосу
  kolonka-widget.py tracks [альбом]  — JSON: альбомы (подпапки ~/Music) и файлы выбранного альбома
"""
import functools
import ipaddress
import json
import os
import re
import shlex
import time
import socket
import subprocess
import sys
from urllib.parse import quote, unquote
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

MAC = "3c:0b:4f:6a:6f:58"
SSH_PORT = 2222
MUSICCTL = "sh /data/opt/bin/musicctl"
MUSIC_PORT = 8000
MUSIC_DIR = Path.home() / "Music"
AUDIO = (".mp3", ".flac", ".ogg", ".m4a", ".wav", ".opus", ".aac")  # как EXTS в music_server.py
VOICE_UNIT = "desktop-voice"
MUSIC = Path(os.environ.get("KOLONKA_DIR") or Path.home() / "Work/kolonka-lite") / "alice-music"
LIVE_SINK = "kolonka_live"
LIVE_STATE = Path(os.environ.get("XDG_RUNTIME_DIR") or "/tmp") / "kolonka-live-sink.json"
SSH = ["ssh", "-i", str(Path.home() / ".ssh/id_ed25519"), "-p", str(SSH_PORT), "-T",
       "-o", "BatchMode=yes", "-o", "ConnectTimeout=4", "-o", "StrictHostKeyChecking=accept-new"]


def run(*cmd):
    return subprocess.run(cmd, capture_output=True, text=True, timeout=5).stdout


def arp_lookup():
    for line in run("ip", "neigh").splitlines():
        # link-local остаётся после перезагрузки колонки, до него ssh не доходит
        if MAC in line.lower() and not line.startswith(("169.254.", "fe80:")):
            return line.split()[0]
    return None


def ping(ip):
    subprocess.run(["ping", "-c1", "-W1", str(ip)], capture_output=True)


def find_speaker():
    ip = arp_lookup()
    if ip:
        return ip
    nets = [ipaddress.ip_interface(m).network
            for m in re.findall(r"inet (\S+)", run("ip", "-4", "-o", "addr", "show", "scope", "global"))]
    # shortcut: пинг-развёртка только по сетям /24 и меньше, большие пропускаем
    hosts = [h for net in nets if net.prefixlen >= 24 for h in net.hosts()]
    with ThreadPoolExecutor(64) as pool:
        list(pool.map(ping, hosts))
    return arp_lookup()


def ssh_open(ip):
    try:
        socket.create_connection((ip, SSH_PORT), timeout=2).close()
        return True
    except OSError:
        return False


def seconds(text):
    parts = [int(p) for p in text.split(":")]
    return sum(p * 60 ** i for i, p in enumerate(reversed(parts)))


def parse_player(text):
    """shortcut: формат mpc (`musicctl status` печатает его), не проверен на живой колонке."""
    info = {"single": False, "live": "/live.mp3" in text.split("\n", 1)[0], "repeat": False, "random": False, "playing": False, "paused": False, "title": "", "artist": "", "elapsed": 0, "total": 0, "volume": None}
    lines = text.splitlines()
    m = re.search(r"\[(playing|paused)\]\s+#\d+/\d+\s+(\S+)/(\S+)", text)
    if m:
        info.update(playing=m[1] == "playing", paused=m[1] == "paused",
                    elapsed=seconds(m[2]), total=seconds(m[3]))
        info["file"] = unquote(lines[0].rsplit("/", 1)[-1]).strip()
        name = re.sub(r"\.\w{2,4}$", "", info["file"])
        artist, _, title = name.partition(" - ")
        info.update(title=title or artist, artist=artist if title else "")
        if info["live"]:
            info.update(title="Звук компьютера", artist="Прямой эфир с ПК", total=0)
    modes = dict(re.findall(r"\b(repeat|random):\s*(on|off)", text))
    modes.update(re.findall(r"\b(single):\s*(on|off)", text))
    info.update(repeat=modes.get("repeat") == "on", random=modes.get("random") == "on",
                single=modes.get("single") == "on")
    # громкость берём из amixer (последний [NN%]): `volume:` у mpc бывает n/a
    amixer = re.findall(r"\[(\d+)%\]", text.split("volume:")[-1])
    info["volume"] = int(amixer[-1]) if amixer else None
    return info


@functools.lru_cache(maxsize=None)
def local_duration(folder, name):
    """mpd не знает длительность файлов, которые читает по HTTP без Range; берём её у файла на ПК."""
    try:
        out = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0",
                              str(folder / name)], capture_output=True, text=True, timeout=5).stdout
        return int(float(out))
    except (ValueError, OSError, subprocess.TimeoutExpired):
        return 0


def move_streams(sink):
    run("pactl", "set-default-sink", sink)
    for line in run("pactl", "list", "short", "sink-inputs").splitlines():
        run("pactl", "move-sink-input", line.split()[0], sink)


def live_sink_on():
    """music_server пишет монитор вывода по умолчанию: уводим звук ПК в пустой sink,
    чтобы он шёл только на колонку, а не ещё и в динамики ноутбука."""
    if LIVE_STATE.exists():
        return
    prev = run("pactl", "get-default-sink").strip()
    module = run("pactl", "load-module", "module-null-sink", f"sink_name={LIVE_SINK}",
                 "sink_properties=device.description=Kolonka").strip()
    LIVE_STATE.write_text(json.dumps({"sink": prev, "module": module}))
    move_streams(LIVE_SINK)


def live_sink_off():
    try:
        state = json.loads(LIVE_STATE.read_text())
    except (OSError, ValueError):
        return
    move_streams(state["sink"])
    run("pactl", "unload-module", state["module"])
    LIVE_STATE.unlink(missing_ok=True)


def status(ip):
    if not ip or not ssh_open(ip):
        ip = find_speaker()
    out = {"state": "missing", "ip": ip, "port": SSH_PORT, "voice": False}
    out["voice"] = subprocess.run(["systemctl", "--user", "is-active", "--quiet", VOICE_UNIT]).returncode == 0
    if ip:
        out["state"] = "nossh"
        if ssh_open(ip):
            out["state"] = "online"
            r = subprocess.run([*SSH, f"root@{ip}", f"{MUSICCTL} status; amixer sget Master"],
                               capture_output=True, text=True, timeout=10)
            out.update(parse_player(r.stdout))
            if out.get("file") and not out["total"] and "/" not in out["file"]:
                out["total"] = local_duration(served_dir() or MUSIC_DIR, out["file"])
    # трансляция кончилась сама (трек из списка, колонка пропала): возвращаем звук в динамики;
    # 15 с форы — пока play.sh --live запускает поток, колонка ещё не в режиме live
    if not out.get("live") and LIVE_STATE.exists() and time.time() - LIVE_STATE.stat().st_mtime > 15:
        live_sink_off()
    return out


def album_names():
    # альбом — подпапка ~/Music (один уровень), "" — сам ~/Music
    return sorted(p.name for p in MUSIC_DIR.iterdir() if p.is_dir() and not p.name.startswith(".")) if MUSIC_DIR.is_dir() else []


def track_names(album=""):
    folder = MUSIC_DIR / album
    # порядок как у playlist() в music_server.py: sorted по имени
    return sorted(p.name for p in folder.iterdir() if p.suffix.lower() in AUDIO) if folder.is_dir() else []


def served_dir():
    """Папка, которую раздаёт запущенный music_server.py (его MUSIC_DIR), или None."""
    for pid in run("pgrep", "-f", "music_server.py").split():
        try:
            env = dict(v.split("=", 1) for v in Path(f"/proc/{pid}/environ").read_text().split("\0") if "=" in v)
        except OSError:
            continue
        return Path(os.path.expanduser(env.get("MUSIC_DIR", "~/Music")))
    return None


def track_script(ip, album, first):
    """Очередь собираем сами: выбранный трек стартует сразу, остальные дописываются следом
    (без запуска трека №1 и без гонки с асинхронной загрузкой m3u в mpd)."""
    names = track_names(album)
    i = names.index(first)
    order = names[i:] + names[:i]  # после последнего трека круг продолжается с начала
    src = re.search(r"src (\S+)", run("ip", "route", "get", ip))
    if not src:
        sys.exit("нет маршрута до колонки")
    folder = MUSIC_DIR / album
    try:
        socket.create_connection(("127.0.0.1", MUSIC_PORT), timeout=1).close()
        up = served_dir() == folder
    except OSError:
        up = False
    if not up:
        # music_server раздаёт одну папку: для другого альбома перезапускаем его на ней
        subprocess.run(["pkill", "-f", "music_server.py"])
        subprocess.Popen(["python3", str(MUSIC / "music_server.py")], start_new_session=True,
                         env={**os.environ, "MUSIC_DIR": str(folder)},
                         stdout=open("/tmp/music-server.log", "w"), stderr=subprocess.STDOUT)
        time.sleep(1)
    urls = [shlex.quote(f"http://{src[1]}:{MUSIC_PORT}/files/{quote(n)}") for n in order]
    mpc = "PATH=/opt/bin:$PATH mpc"
    return f"{mpc} clear && {mpc} add {urls[0]} && {mpc} play && " + " && ".join(f"{mpc} add {u}" for u in urls[1:])


def ctl(ip, action, arg):
    if action == "play":
        cmd = ["bash", str(MUSIC / "play.sh")]
    elif action == "pc-audio":
        cmd = ["bash", str(MUSIC / "play.sh"), "--live"]
    elif action == "voice-on":
        cmd = ["systemctl", "--user", "restart", VOICE_UNIT]
    elif action == "voice-off":
        cmd = ["systemctl", "--user", "stop", VOICE_UNIT]
    elif action == "stop":
        cmd = ["bash", str(MUSIC / "stop.sh")]
    elif action in ("pause", "resume", "next", "prev"):
        cmd = [*SSH, f"root@{ip}", f"{MUSICCTL} {action}"]
    elif action == "track" and (track := arg.rpartition("/"))[0] in ["", *album_names()] and track[2] in track_names(track[0]):
        cmd = [*SSH, f"root@{ip}", track_script(ip, track[0], track[2])]
    elif action == "random" and arg in ("on", "off"):
        # shortcut: mpc лежит в Entware (/opt/bin), как и сам mpd; на живой колонке не проверено
        cmd = [*SSH, f"root@{ip}", f"PATH=/opt/bin:$PATH mpc random {arg}"]
    elif action == "repeat" and arg in ("off", "all", "one"):
        # all — повтор плейлиста; one — повтор трека (mpc: repeat + single)
        rep, single = {"off": ("off", "off"), "all": ("on", "off"), "one": ("on", "on")}[arg]
        cmd = [*SSH, f"root@{ip}", f"PATH=/opt/bin:$PATH mpc single {single}; PATH=/opt/bin:$PATH mpc repeat {rep}"]
    elif action == "volume" and arg.isdigit() and 0 <= int(arg) <= 100:
        cmd = [*SSH, f"root@{ip}", f"amixer sset Master {int(arg)}%"]
    else:
        sys.exit("неизвестная команда")
    if action == "pc-audio":
        live_sink_on()
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
    if action == "stop" or action == "pc-audio" and r.returncode:
        live_sink_off()
    if r.returncode:
        sys.exit(((r.stderr or r.stdout).strip().splitlines() or ["ошибка"])[-1])


if __name__ == "__main__":
    args = sys.argv[1:] + ["", ""]
    if args[0] == "status":
        print(json.dumps(status(args[1])))
    elif args[0] == "tracks":
        albums = album_names()
        album = args[1] if args[1] in albums else ""
        print(json.dumps({"albums": albums, "album": album, "tracks": track_names(album)}))
    elif args[0] == "ctl":
        ctl(args[1], args[2], args[3])
