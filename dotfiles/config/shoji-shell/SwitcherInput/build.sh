#!/usr/bin/env bash
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT
"$(pkg-config --variable=libexecdir Qt6Core)/moc" "$root/inputstate.h" -o "$work/moc_inputstate.cpp"
"$(pkg-config --variable=libexecdir Qt6Core)/moc" $(pkg-config --cflags Qt6Qml) "$root/plugin.cpp" -o "$work/plugin.moc"
g++ -std=c++17 -fPIC -shared -Wall -Wextra -Werror \
    $(pkg-config --cflags Qt6Core Qt6Gui Qt6Qml wayland-client) \
    -I"$root" -I"$work" "$root/plugin.cpp" "$work/moc_inputstate.cpp" \
    -o "$work/libswitcherinputplugin.so" \
    $(pkg-config --libs Qt6Core Qt6Gui Qt6Qml wayland-client)
install -m 755 "$work/libswitcherinputplugin.so" "$root/libswitcherinputplugin.so"

# The installer renders the native path in the installed qmldir only.
