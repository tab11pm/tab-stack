# Remaining system-source synchronization

The fresh public main already contains the widget library/editor, night-light
schedule, optional automatic sleep, activity charts, battery/power profiles,
MPRIS music controls, OpenCode sessions and the independent session lifecycle.
These components are retained rather than replaced with older machine copies.

This update ports the remaining reviewed deltas:

- Primary/secondary output roles in the widget editor, including missing-output
  handling and compatibility with saved explicit connector names.
- Super+D show-desktop/restore and one-way Super+Up/Down window actions.
- Claude Code OAuth quota collection beside Codex, shared five-minute cache,
  and updated Home Zone and standalone limits rows.
- Live wallpaper filtering after output disconnection and recovery after the
  wallpaper renderer exits without changing the saved selection.
- Monitor socket recreation after failed connections, isolated invalid-mode
  fallback when a different display occupies a connector, and state fetching
  after a rejected saved profile.
- The passive native Qt switcher input helper, with source-only publication,
  local build and installation-time library path rendering.
- Lock PAM selection that uses its own service or its bundled platform fallback.

The publication retains source-side type corrections, protected recovery/switcher
shortcuts, custom-command limits, the standalone DeepSeek card and its input
region, and modal-editor guards. It keeps autosleep and account integrations off
by default. Activity history additionally requires `SHOJI_ENABLE_ACTIVITY=1` in
both QML and Python. Installed personal defaults are not exported.

No credentials, local integration files, profiles, history, library selections,
personal wallpapers, runtime state or backups are included. Desktop edits are
not installed over the working session by this synchronization. The repository
installer is tested only with a temporary target home.

The native helper needs a local Qt 6 build; see [installation](install.md).
Offscreen and fake-compositor checks do not establish real multi-output, GPU,
lock/suspend or keyboard behavior in a live session. Full compositor rebuilding
and clean-user acceptance remain separate checks.
