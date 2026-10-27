# Switcher input observation

This Qt 6 QML plugin handles Alt released before the switcher window maps.
It observes the actual focused QWindow, waits for an asynchronous Wayland sync,
and checks keyboard modifiers. It never grabs or synthesizes keys. The QML
overlay continues to handle ordinary Alt releases itself.

Build from the repository root with `bash dotfiles/scripts/build-switcher-input.sh`.
Run the isolated focus checks with `bash dotfiles/config/shoji-shell/SwitcherInput/check.sh`.

Requires Qt 6 Core, Gui and Qml development packages, wayland-client, pkg-config,
a C++17 compiler and Qt 6 moc. Tests also require Qt 6 Test. The build generates
an ignored shared library; the installer copies it and renders the real native
library path in the installed qmldir. Quickshell's virtual QML filesystem cannot
load a native library using its relative virtual path. Rebuild after a Qt ABI
change. Offscreen tests do not establish live Wayland switching behavior.
