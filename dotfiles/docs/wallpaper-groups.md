# Wallpaper groups

Open **Super+W → Изображения** (Images). The **Группа** (Group) selector above
the carousel filters the static image library into named collections.

1. Choose **Новая группа** (New group), enter a name and check the photos to include.
2. Choose **Сохранить** (Save), then browse the group in the existing carousel.
3. Apply a photo and widget preset together with Enter, as before.

**Изменить** (Edit) renames a group or changes its membership. **Отмена** (Cancel)
and Escape discard the editor draft. Deleting a group requires confirmation and
leaves the photos in place. **Все изображения** (All images) returns to the full
library.

A photo may belong to several groups. Empty groups are allowed and provide an
action to add photos; they cannot apply a wallpaper. Temporarily missing photos
remain in the saved membership and reappear when restored to the library.
Grouping does not move, copy or delete image files. Animated wallpapers retain
their separate library. There is no automatic schedule.

## Keyboard controls

- **G** focuses the group row; **Left/Right** select a group.
- **N** opens a new group; **E** edits the selected group.
- **Up/Down**, **Tab** and **Shift+Tab** move between picker rows.
- In the editor, **Tab** moves between controls and **Space** toggles a photo.
- **Escape** cancels the editor; another Escape closes the picker.

## Local state and installation

Groups, photo URLs and the last selected group are stored in the installed
`shoji-shell/wallpaper-groups.json`, separately from `wallpapers.json`. Writes are
atomic. Invalid group state shows an error rather than being overwritten.
Group names must be unique ignoring case and contain 1–64 characters.

The installer preserves this state when updating the shell. The file is ignored
by Git, excluded from installation source copies and rejected by the publication
privacy checker. Do not publish group state or personal photos.

## Source check

From the repository root:

```bash
node dotfiles/config/shoji-shell/wallpaper-groups-check.mjs
```

The check covers naming, overlapping membership, filtering, serialization,
missing files and group deletion with synthetic photo URLs.
