#!/usr/bin/env bash
# One-command tab-stack install for a fresh Arch system. Chains the existing
# build/install scripts; safe to re-run. Does not touch GPU drivers.
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
with_sleep_lock=0
for arg in "$@"; do
    case "$arg" in
        --with-sleep-lock) with_sleep_lock=1 ;;
        -h|--help) echo "Usage: $0 [--with-sleep-lock]"; exit 0 ;;
        *) echo "Unknown option: $arg" >&2; exit 2 ;;
    esac
done
step() { printf '\n==> %s\n' "$*"; }
die() { echo "Error: $*" >&2; exit 1; }

# Copy a root-owned file into place: absent or identical is fine, anything else stops.
install_root_file() {
    local source="$1" destination="$2"
    if [[ -L "$destination" ]]; then die "$destination is a symlink; refusing"; fi
    if [[ -e "$destination" ]]; then
        cmp -s -- "$source" "$destination" && { echo "Already installed: $destination"; return; }
        die "$destination exists with other content; review it and install by hand (see docs)"
    fi
    sudo install -D -o root -g root -m 644 -- "$source" "$destination"
    echo "Installed $destination"
}

step 'Preflight'
[[ -f /etc/arch-release ]] || die 'this script is for Arch Linux'
[[ "$(id -u)" -ne 0 ]] || die 'run as your desktop user, not root'
command -v sudo >/dev/null || die 'sudo is required'
if systemctl --user is-active --quiet tab-stack-session.target 2>/dev/null; then
    die 'tab-stack session is running; log out and run this from a TTY or another desktop'
fi
sudo -v

step 'Arch packages'
mapfile -t packages < <(grep -hv -e '^#' -e '^$' "$root/dependencies/arch.txt")
if [[ "$with_sleep_lock" -eq 1 ]]; then
    mapfile -t -O "${#packages[@]}" packages < <(grep -hv -e '^#' -e '^$' "$root/dependencies/sleep-lock-arch.txt")
fi
sudo pacman -S --needed "${packages[@]}" sddm
rustup toolchain install 1.94.0

step 'Elephant from AUR'
aur="$(command -v paru || command -v yay || true)"
if [[ -z "$aur" ]]; then
    work="$(mktemp -d)"
    git clone https://aur.archlinux.org/paru-bin.git "$work/paru-bin"
    (cd "$work/paru-bin" && makepkg -si --noconfirm)
    rm -rf -- "$work"
    aur="$(command -v paru)"
fi
"$aur" -S --needed elephant-bin elephant-desktopapplications-bin elephant-files-bin elephant-providerlist-bin

step 'ShojiWM compositor'
# shortcut: an installed /usr/bin/shoji_wm is kept; remove it to pick up a new pinned revision.
if [[ -x /usr/bin/shoji_wm ]]; then
    echo 'Already installed: /usr/bin/shoji_wm'
else
    "$root/scripts/build-shojiwm.sh"
    checkout="$(ls -td "$root"/.build/shojiwm.*/ | head -n 1)"
    (cd "$checkout" && ./dist/install.sh --no-build --no-config)
fi

step 'Patched Quickshell'
# install.py refuses to install shoji-shell without it.
if [[ -x "${XDG_DATA_HOME:-$HOME/.local/share}/shoji-shell/quickshell/bin/quickshell" ]]; then
    echo 'Already installed: patched Quickshell'
else
    "$root/scripts/build-quickshell.sh"
    cmake --install "$(ls -td "$root"/.build/quickshell.*/ | head -n 1)build"
fi

step 'Walker, shaders, switcher input'
"$root/scripts/build-walker.sh"
"$root/scripts/build-shaders.sh"
"$root/scripts/build-switcher-input.sh"

step 'User files and session'
python3 "$root/scripts/install.py" --apply
python3 "$root/scripts/install.py" --component session --apply
python3 "$root/scripts/migrate-session.py" --apply
if [[ "$with_sleep_lock" -eq 1 ]]; then
    python3 "$root/scripts/install.py" --component sleep-lock --apply
fi
systemctl --user daemon-reload
mkdir -p "$HOME/Pictures/Wallpapers"

step 'Login manager'
install_root_file "${XDG_STATE_HOME:-$HOME/.local/state}/tab-stack/session/tab-stack.desktop" \
    /usr/local/share/wayland-sessions/tab-stack.desktop
install_root_file "$root/system/sddm/zz-tab-stack-greeter.conf" /etc/sddm.conf.d/zz-tab-stack-greeter.conf
sudo systemctl enable sddm.service bluetooth.service

step 'Done'
systemctl is-enabled --quiet NetworkManager.service 2>/dev/null \
    || echo 'Note: NetworkManager is not enabled; the panel network controls need it.'
case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) echo "Note: add $HOME/.local/bin to PATH." ;; esac
echo 'Wi-Fi passwords need a NetworkManager secret agent (e.g. nm-applet); none is installed.'
echo 'Reboot, choose "tab-stack" in SDDM. Recovery: Ctrl+Alt+F3 and docs/install.md "Restore or remove".'
