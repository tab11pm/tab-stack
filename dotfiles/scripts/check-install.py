#!/usr/bin/env python3
"""Exercise preview, installation and backup preservation in a disposable home."""
from pathlib import Path
import json
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    with tempfile.TemporaryDirectory(prefix="tab-stack-check-") as directory:
        home = Path(directory) / "desktop user"
        home.mkdir()
        args = [sys.executable, str(ROOT / "scripts/install.py"), "--target-home", str(home)]
        subprocess.run(args, check=True, capture_output=True)
        assert not list(home.iterdir()), "Preview wrote files"
        subprocess.run([*args, "--apply"], check=True, capture_output=True)
        config = home / ".config"
        assert config.joinpath("shojiwm/node_modules/shoji_wm").is_symlink()
        assert config.joinpath("shoji-shell/shaders/widget-wave-mask.frag.qsb").is_file()
        assert str(home) in config.joinpath("elephant/files.toml").read_text()
        local = config / "shoji-shell/integrations.env"
        local.write_text("SHOJI_ENABLE_GITHUB=0\n# local setting\n")
        groups = config / "shoji-shell/wallpaper-groups.json"
        group_state = {"version": 1, "selected": "group_fixture", "groups": [
            {"id": "group_fixture", "name": "Night", "images": ["file:///tmp/wallpaper-groups-fixture/night.png"]}
        ]}
        groups.write_text(json.dumps(group_state) + "\n")
        monitors = config / "shoji-shell/monitors.json"
        monitor_state = {"primary": "DP-1", "outputs": [
            {"name": "DP-1", "x": 0, "y": 0, "scale": 1,
             "width": 1920, "height": 1080, "refreshRate": 60}
        ]}
        monitors.write_text(json.dumps(monitor_state) + "\n")
        user_file = config / "ghostty/user-note"
        user_file.write_text("preserve in backup\n")
        subprocess.run([*args, "--apply"], check=True, capture_output=True)
        assert "local setting" in local.read_text()
        assert json.loads(groups.read_text()) == group_state, "Reinstall lost wallpaper groups"
        assert config.joinpath("shoji-shell/WallpaperGroups.qml").is_file()
        assert config.joinpath("shoji-shell/WallpaperGroupEditor.qml").is_file()
        assert json.loads(monitors.read_text()) == monitor_state, "Reinstall lost monitor settings"
        for name in ("Monitors.qml", "MonitorSettings.qml", "MonitorChoice.qml"):
            assert config.joinpath("shoji-shell", name).is_file()
        assert config.joinpath("shojiwm/src/monitors.ts").is_file()
        manifests = list(home.glob(".local/state/tab-stack/backups/*/manifest.json"))
        assert len(manifests) == 2
        backed_up = [Path(e["backup"]) for m in manifests for e in json.loads(m.read_text()) if e["backup"]]
        assert any((p / "user-note").is_file() for p in backed_up)
        assert (home / ".local/bin/codex-resume-ghostty").stat().st_mode & 0o111
        print("Preview, isolated install, generated paths, runtime link, wallpaper groups, monitor settings and second-install backups: OK")


if __name__ == "__main__":
    main()
