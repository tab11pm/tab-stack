#!/usr/bin/env bash
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT
qt_moc="$(pkg-config --variable=libexecdir Qt6Core)/moc"
"$qt_moc" "$root/inputstate.h" -o "$work/moc_inputstate.cpp"
"$qt_moc" "$root/test_inputstate.cpp" -o "$work/test_inputstate.moc"
g++ -std=c++17 -fPIC $(pkg-config --cflags Qt6Core Qt6Gui Qt6Test wayland-client) \
    -I"$root" -I"$work" "$root/test_inputstate.cpp" "$work/moc_inputstate.cpp" \
    -o "$work/test_inputstate" $(pkg-config --libs Qt6Core Qt6Gui Qt6Test wayland-client)
QT_QPA_PLATFORM=offscreen "$work/test_inputstate"
