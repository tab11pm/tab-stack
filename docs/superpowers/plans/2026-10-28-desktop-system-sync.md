# Remaining desktop source synchronization

> **For agentic workers:** Use superpowers:executing-plans for the selected source deltas, followed by one independent final review.

**Goal:** Bring the remaining reviewed installed behavior and bug fixes into a fresh tab-stack source branch.

**Architecture:** Start from fetched origin/main (617d49b), which already contains the editor, night light, idle sleep, activity, battery, music, OpenCode and independent session. Port only the missing delta; retain publication fixes and permission gates that are newer than the installed source.

**Tech Stack:** ShojiWM TypeScript, Quickshell/QML, Qt 6 C++, Python, Node.

**Spec:** User's review-and-sync request; dotfiles/AGENTS.md and dotfiles/docs/privacy.md.

## Constraints

- Installed desktop is read-only during this task. No reloads or real integrations.
- Never transfer credentials, runtime profiles/history, binaries, backups or personal documentation.
- Preserve newer source type fixes, protected shortcuts, standalone DeepSeek card, disabled account integrations and disabled autosleep.
- Activity accounting must require explicit opt-in in both QML and its Python entrypoint.
- Local preparation only; no remote publication or merge into another active branch.

## Tasks

- [x] 1. Port monitor/profile and wallpaper recovery fixes; package the passive Alt-release helper as portable source. Render its native path only in installed copies; verify build, offscreen focus and isolated reinstall.
- [x] 2. Port monitor roles in layout editor, live wallpaper hotplug filtering, Super+D/Up/Down and Claude quota reading. Verify roles with changed/disconnected primary, window restore membership/focus, provider normalization/cache and the disabled entrypoint.
- [x] 3. Preserve privacy defaults and introduce explicit activity opt-in. Verify a disabled direct collector creates no database, opt-in tracking tests remain green, and private profiles survive reinstall.
- [x] 4. Update install/configuration/privacy/validation docs; run source checks, QML lint, isolated installation, privacy checks and independent code review. Leave a reviewable local branch.

## Review focus

- Native plugin paths must work when a target home contains spaces.
- Replacing a monitor must not reject other saved entries.
- Missing secondary output must not put its widgets on the primary output.
- Show-desktop must restore only windows it minimized and ignore windows closed in between.
- Direct collectors must respect opt-in before reading credentials or creating history.
