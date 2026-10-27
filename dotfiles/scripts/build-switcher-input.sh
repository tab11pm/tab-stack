#!/usr/bin/env bash
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
bash "$root/config/shoji-shell/SwitcherInput/build.sh"
