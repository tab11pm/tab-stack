# Optional widget integrations

The appearance works without any account. All account/session integrations and
weather are **disabled by default**, including on a machine whose CLIs are already
authenticated. Presets define placement; `Settings.enabled()` is an independent
permission gate before widget loaders become active. Python/Node collectors also
refuse direct execution unless their own enable flag is set.

Copy the example into the **installed**, local shell directory:

```bash
cp "${XDG_CONFIG_HOME:-$HOME/.config}/shoji-shell/integrations.env.example" \
   "${XDG_CONFIG_HOME:-$HOME/.config}/shoji-shell/integrations.env"
chmod 600 "${XDG_CONFIG_HOME:-$HOME/.config}/shoji-shell/integrations.env"
```

Edit only the flags you want, then restart the shell when ready. `scripts/start-shell`
sources this trusted shell file before starting Quickshell. Never source a stranger's
integration file. It should contain flags, paths and optional weather locations,
not API keys. CLI authentication remains owned by each locally installed CLI;
DeepSeek reads a separate local key file after explicit opt-in.

| Flag | Prerequisites and access after opt-in |
| --- | --- |
| `SHOJI_ENABLE_GITHUB=1` | `gh` logged into **your** account; reads notifications, PRs, issues and discussion replies. Does not mark notifications read. Writes a local cache. |
| `SHOJI_ENABLE_DEEPSEEK=1` | Your DeepSeek API key in a separate private file; polls balance, caches locally and estimates spend from observed decreases. Does not submit model requests. |
| `SHOJI_ENABLE_LIMITS=1` | Node.js and your installed/authenticated Codex CLI; queries quotas through its local protocol adapter. Missing providers show unavailable. CLI token refresh may update the CLI's own credential store. |
| `SHOJI_ENABLE_SESSIONS=1` | Your local Codex/OpenCode session stores; reads titles and working-directory metadata. Clicking a session copies its resume command using `wl-copy`; it does not run it. Widget archiving writes its own local SQLite index. |
| `SHOJI_ENABLE_HERMES=1` | A compatible Hermes checkout/venv with `tui_gateway.entry`; starts only when you submit a message. It is a real agent with your configured tools, permissions and model costs. |
| `SHOJI_ENABLE_WEATHER=1` | `SHOJI_WEATHER_CITIES` with exactly two `[id,name,latitude,longitude]` entries. Sends those coordinates to Open-Meteo; no API key is required. |

Hermes uses `${HOME}/.hermes/hermes-agent` by default; override `SHOJI_HERMES_ROOT`.
Its adapter expects JSON-RPC methods such as `session.create`, `prompt.submit`,
`session.interrupt` and approval/secret response messages. An arbitrary Hermes
release is not guaranteed to implement this protocol. The desktop bundle does
not install an agent, enable tools or copy any model configuration for you.

The limits and session adapters track particular CLI protocols/schema versions;
those can change independently of the desktop. Check their source when updating
a CLI. A missing quota is not a zero balance. No token is supplied in this repository.

## DeepSeek API balance

Vast.ai tiles have been replaced by DeepSeek balance and estimated spend in
Home Zone and the default preset. Set `SHOJI_ENABLE_DEEPSEEK=1` locally, then put
your key in the installed `shoji-shell/deepseek-api-key` with mode `600`, or set
`DEEPSEEK_API_KEY_FILE` to an existing private file. `DEEPSEEK_API_KEY` is also
accepted from the local process environment; do not put it in repository files
or command arguments. The installer preserves the default key file on reinstall.
No key is supplied by the stack, and the collector refuses execution before
reading credentials or accessing the network unless the flag is exactly `1`.

The collector polls the balance endpoint at most once per minute per key and
writes an atomic private ledger under `$XDG_STATE_HOME/shoji-shell/deepseek`.
USD and CNY are kept separate. Spend is marked **≈**: it accumulates observed
balance decreases since the first sample for that key/currency, rather than an
invoice or monthly billing total. Top-ups between samples can hide usage.
Changing currency resets the estimate; removing the local ledger starts a new
observation period. Missing keys, authentication errors and stale data are shown
without printing raw responses or credential details.

## Sessions and provider status

The sessions widget now has Codex and OpenCode tabs. OpenCode metadata is read
from `$XDG_DATA_HOME/opencode/opencode.db` in read-only mode; archived sessions
and child sessions are excluded. The widget copies `opencode --session <id>`
from the session's directory, and never starts the agent. Its own archive remains
separate from OpenCode's database.

Quota displays now query Codex only; OpenCode sessions do not imply an OpenCode
quota source. The public status row selects OpenAI, Claude and DeepSeek. Legacy
Grok/Kimi parsing remains available in the quota adapter for explicit reuse, but
these widgets do not launch those CLIs.

## Music and battery

Music uses standard MPRIS metadata from browser/web players. The widget adds
previous/play-pause/next and seek controls when the chosen player supports them,
and retains a paused player so playback can resume. It prefers the captured
process ID; ambiguous players or a MateEngine capture do not receive browser
transport commands. Controls can work without a spectrum capture. The spectrum
uses a local PipeWire/PulseAudio recording stream and NumPy FFT processing;
it does not upload audio. Neko still reacts to the music energy. Private music
catalogs, artwork paths and site-specific adapters are not included.

The battery panel uses UPower for charge, health and time estimates. Its panel
button is hidden when no battery is present. With `power-profiles-daemon`
available, it lists the supported profiles and invokes `powerprofilesctl set`
only when you choose a profile. Missing service/access errors are shown locally.

Local caches and session metadata can contain private repository names, discussion
titles, rental labels and prompts. They are not publication material. Do not copy
`~/.cache/shoji-shell`, `~/.local/state/shoji-shell`, CLI homes or `integrations.env`
back into this repository. Disable integrations before recording a public demo.

## Widget source references

This export keeps the existing desktop design system. The standalone DeepSeek
card follows `VastWidget.qml`/`WidgetSurface.qml`: 286-pixel width, 16-pixel content
inset, compact rows, existing grain and the Mocha ink/muted/danger roles.
`HomeAccounts.qml` supplies the balance and estimate labels; `ActionButton.qml`
supplies the cabinet action and focus/hover behavior. Refero's bundled craft
focus guidance informs retaining named controls and visible focus states.
The installed music and battery components retain their existing visual treatment.

| Decision | Reference and role |
| --- | --- |
| Card width, insets and row density | Existing standalone account widget |
| Mocha text, surfaces and stale/error indicator | `Theme.qml` and `WidgetSurface.qml` |
| Approximate-spend label and local error text | Installed Home Zone account tiles |
| Named action and keyboard focus | `ActionButton.qml`, Refero craft focus guidance |

A synthetic offscreen preview checked available, missing-key and authentication
error states without enabling the account collector. The layout and colors were
compared with these source references; no personal desktop screenshot is bundled.
