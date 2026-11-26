#!/usr/bin/env python3
"""Помощник виджета колонки.

  kolonka-widget.py status [ip]      — одна JSON-строка: состояние колонки и плеера
  kolonka-widget.py ctl ip action [arg] — команда плееру/голосу
  kolonka-widget.py tracks            — JSON-список файлов из ~/Music
"""
import ipaddress
import json
import os
import re
import socket
import subprocess
import sys
from urllib.parse import unquote
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

MAC = "3c:0b:4f:6a:6f:58"
SSH_PORT = 2222
MUSICCTL = "sh /data/opt/bin/musicctl"
MUSIC_DIR = Path.home() / "Music"
AUDIO = (".mp3", ".m4a", ".wav", ".flac", ".ogg", ".opus")
VOICE_UNIT = "desktop-voice"
MUSIC = Path(os.environ.get("KOLONKA_DIR") or Path.home() / "Work/kolonka-lite") / "alice-music"
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
    info = {"live": "/live.mp3" in text.split("\n", 1)[0], "repeat": False, "random": False, "playing": False, "paused": False, "title": "", "artist": "", "elapsed": 0, "total": 0, "volume": None}
    lines = text.splitlines()
    m = re.search(r"\[(playing|paused)\]\s+#\d+/\d+\s+(\S+)/(\S+)", text)
    if m:
        info.update(playing=m[1] == "playing", paused=m[1] == "paused",
                    elapsed=seconds(m[2]), total=seconds(m[3]))
        name = re.sub(r"\.\w{2,4}$", "", unquote(lines[0].rsplit("/", 1)[-1])).strip()
        artist, _, title = name.partition(" - ")
        info.update(title=title or artist, artist=artist if title else "")
        if info["live"]:
            info.update(title="Звук компьютера", artist="Прямой эфир с ПК", total=0)
    modes = dict(re.findall(r"\b(repeat|random):\s*(on|off)", text))
    info.update(repeat=modes.get("repeat") == "on", random=modes.get("random") == "on")
    # громкость берём из amixer (последний [NN%]): `volume:` у mpc бывает n/a
    amixer = re.findall(r"\[(\d+)%\]", text.split("volume:")[-1])
    info["volume"] = int(amixer[-1]) if amixer else None
    return info


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
    return out


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
    elif action == "track" and arg and "/" not in arg:
        cmd = ["bash", str(MUSIC / "play.sh"), arg]
    elif action in ("repeat", "random") and arg in ("on", "off"):
        # shortcut: mpc лежит в Entware (/opt/bin), как и сам mpd; на живой колонке не проверено
        cmd = [*SSH, f"root@{ip}", f"PATH=/opt/bin:$PATH mpc {action} {arg}"]
    elif action == "volume" and arg.isdigit() and 0 <= int(arg) <= 100:
        cmd = [*SSH, f"root@{ip}", f"amixer sset Master {int(arg)}%"]
    else:
        sys.exit("неизвестная команда")
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
    if r.returncode:
        sys.exit(((r.stderr or r.stdout).strip().splitlines() or ["ошибка"])[-1])


if __name__ == "__main__":
    args = sys.argv[1:] + ["", ""]
    if args[0] == "status":
        print(json.dumps(status(args[1])))
    elif args[0] == "tracks":
        print(json.dumps(sorted(p.name for p in MUSIC_DIR.iterdir() if p.suffix.lower() in AUDIO)
                         if MUSIC_DIR.is_dir() else []))
    elif args[0] == "ctl":
        ctl(args[1], args[2], args[3])
