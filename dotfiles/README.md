# tab-stack desktop

This is the desktop part of **tab-stack**, maintained by **Tabek** as part of
**Alt Tabek**. I adapt my working environment around development, automation and
AI-assisted workflows, and publish the configuration source here.

The desktop combines ShojiWM, Quickshell, a customized Walker launcher and
Catppuccin Mocha colors. It grew from howdeploy's kisa-stack configuration;
its source ancestry and component licenses are retained in [NOTICE.md](NOTICE.md).
The development repository is [tab11pm/tab-stack](https://github.com/tab11pm/tab-stack).

## What I am developing here

The published configuration includes:

- A [custom session lock](config/shoji-shell/lock/README.md) with shared password
  entry across outputs, plus an [opt-in managed session](docs/session.md).
- [Monitor controls](docs/monitors.md) for layout, primary output, brightness,
  refresh rate and scale, with a timed rollback for mode changes.
- A widget layout editor, MRU window switcher, scheduled night filter,
  optional idle sleep and local activity accounting. See the
  [October 12 update](docs/update-2026-10-12.md).
- [Music transport and seek controls, battery/power profiles and optional
  account/session widgets](docs/widgets.md).
- Wallpaper and layout transitions, screen effects and procedural shaders,
  alongside the inherited desktop components.

The repository holds portable configuration source and installation tools.
Personal wallpapers, credentials, account data and saved profiles stay local.
The shell starts with the **empty** preset and a neutral SVG background.
Account integrations and automatic sleep remain off until explicitly enabled.

## Get started

1. Read [installation](docs/install.md) for dependencies, pinned builds,
   preview/install steps and recovery. Arch/Manjaro is the reference environment.
2. Use [configuration](docs/configuration.md) for shortcuts, displays,
   wallpaper/layout choices, terminal and launcher settings.
3. Choose only the [optional integrations](docs/widgets.md) you need and supply
   your own local authentication.
4. For a separate login entry, follow [session setup](docs/session.md).
   The [X11 greeter configuration](docs/greeter.md) is a separate system option.
5. For source changes, read [architecture](docs/architecture.md), the
   [shader guide](docs/shaders.md) and [AGENTS.md](AGENTS.md).

Use the **howdeploy/ShojiWM integration revision pinned in
[sources.json](sources.json)**. The config relies on APIs and fixes from that
fork; a moving branch name or another upstream build is not an equivalent
runtime. [Fork provenance](docs/fork.md) records which contributions came from
upstream and howdeploy.

## Source map

| Directory | Contents |
| --- | --- |
| `config/shojiwm/` | TSX compositor configuration, window management, GLSL effects and session helpers |
| `config/shoji-shell/` | QML panels, widgets, editors, Qt shaders and local collectors |
| `config/walker/`, `patches/walker/` | Launcher theme and source patch |
| `config/elephant/` | Launcher providers and portable file search |
| `config/ghostty/` | Terminal styling and keyboard shortcuts |
| `config/xdg-desktop-portal/` | Portal backend selection |
| `config/systemd/user/`, `system/` | Optional managed-session units and system configuration sources |
| `data/icons/Shoji/` | Local SVG override theme inheriting Papirus Dark |
| `bin/` | Codex session chooser and managed-session launcher |
| `scripts/` | Build, preview/install, migration and publication checks |
| `docs/`, `dependencies/` | Setup, behavior, validation and provenance |

## Working with agents

Three desktop skills are available in the repository catalog:

- [shojiwm](../skills/shojiwm/SKILL.md) — understand and modify the desktop.
- [shoji-shaders](../skills/shoji-shaders/SKILL.md) — work with effects and
  preserve their animation lifecycle.
- [tab-stack-feature](../skills/tab-stack-feature/SKILL.md) — prepare selected
  changes, validate them and publish to the tab-stack fork when requested.

From the repository root:

```bash
./install.sh shojiwm --codex
./install.sh shoji-shaders --codex
./install.sh tab-stack-feature --codex
```

The installer also accepts `--claude` and `--hermes`; check each skill's
requirements before using it in another environment.

## Status and next steps

This desktop is evolving around my own setup. The [validation record](docs/validation.md)
distinguishes source checks and temporary-home installation from native graphical,
cold-boot and clean-machine acceptance. Those remaining checks guide the next
round of work; publication is not a claim of universal GPU/distribution support.

The [October 4 source snapshot](docs/update-2026-10-04.md) documents the inherited
wallpaper/effect baseline. Later updates and their validation are recorded
separately, so an older result should not be read as proof of a newer change.

Read [privacy](docs/privacy.md) before exporting files or screenshots. Issues
and contributions belong in [tab-stack](https://github.com/tab11pm/tab-stack/issues).

The [remaining system-source synchronization](docs/system-sync.md) records the
latest monitor roles, window actions, Claude quotas, wallpaper recovery and
passive Alt-release helper, together with opt-in and validation boundaries.
