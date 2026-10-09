# Monitor settings

Open the system panel → **Мониторы** (Monitors). Select a screen in the diagram
or by connector name. Dragging snaps its edges to another output without overlap;
arrow keys move the focused screen by 20 logical pixels. Enter selects it.
**Сделать главным** chooses the primary output for the panel, dock and widgets
whose placement is `primary`.

Refresh rates come from driver-reported modes for the current resolution. The
panel also offers scale selection; resolution selection is not exposed.
**Применить** applies layout/primary changes immediately. A refresh-rate or scale
change starts a 15-second preview: **Сохранить** confirms, **Вернуть** cancels.
Without confirmation, the compositor restores the previous configuration even
if the shell is unavailable. **Сбросить** discards an unapplied draft.

Confirmed settings are written atomically to the installed
`shoji-shell/monitors.json`. Disconnected outputs remain in the profile. When the
chosen primary is absent, the shell uses the first available output. New outputs
without a profile use automatic extension, their best mode and scale 1. Changing
the connected output list clears a stale draft. Saved settings also survive a
compositor configuration reload and a dotfiles reinstall.

Brightness remains in **Звук и экран** (Sound and screen). Internal eDP/LVDS/DSI
outputs use sysfs backlight readings and `brightnessctl` for explicit writes;
external displays use `ddcutil` and DDC/CI. Device access follows the distribution's
normal rules; this feature does not change permissions. Hardware without a usable
backlight or DDC/CI reports an error beside the control.

After installing the updated source, reload ShojiWM deliberately with
`Super+Shift+R` to register the new IPC methods. Publishing this source does not
reload the running desktop. No personal `monitors.json` is bundled.

Source checks, without connecting to desktop IPC:

```bash
node dotfiles/scripts/check-monitors.mjs
python3 dotfiles/config/shoji-shell/brightness.py --check
python3 dotfiles/scripts/check-install.py
```

The Node check requires Node 22.13+ with `stripTypeScriptTypes`. It uses a fake
compositor and timer; it cannot establish native mode switching or hotplug behavior.
Before relying on this on another machine, verify the diagram, primary selection,
scale/refresh confirmation, timed rollback, reconnect and brightness on that
machine's outputs. See [validation](validation.md) for the export checks.
