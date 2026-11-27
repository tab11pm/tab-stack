"""Current Unix account's display name and portrait (~/.face, else AccountsService)."""
import json
import os
from pathlib import Path
import pwd
import sys


def profile(account, home=None):
    face = Path(home or account.pw_dir) / ".face"
    return {
        "name": account.pw_gecos.split(",", 1)[0].strip() or account.pw_name,
        "avatar": (face if face.is_file() else Path("/var/lib/AccountsService/icons") / account.pw_name).as_uri(),
    }


if __name__ == "__main__":
    if sys.argv[1:] == ["--self-check"]:
        from types import SimpleNamespace

        assert profile(SimpleNamespace(pw_name="user", pw_gecos="Имя,room,phone", pw_dir="/nonexistent"))["name"] == "Имя"
        assert profile(SimpleNamespace(pw_name="user", pw_gecos=" ,room", pw_dir="/nonexistent"))["name"] == "user"
        assert profile(SimpleNamespace(pw_name="a b", pw_gecos="", pw_dir="/nonexistent"))["avatar"].endswith("/a%20b")
        import tempfile
        with tempfile.TemporaryDirectory() as home:
            (Path(home) / ".face").write_bytes(b"")
            assert profile(SimpleNamespace(pw_name="u", pw_gecos="", pw_dir=home))["avatar"].endswith("/.face")
        print("Profile: GECOS name, login fallback and local image URL OK")
    else:
        print(json.dumps(profile(pwd.getpwuid(os.getuid())), ensure_ascii=False))
