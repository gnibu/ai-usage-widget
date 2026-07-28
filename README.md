# ai-usage-widget

How much of your **Claude Code** and **Codex** quota you have burned, and
whether you are burning it faster than the window refills. Refreshes every 15
minutes.

```
AI USAGE                          05:07
Claude                             MAX
5h          ▓▓▓─┃──────   18%     07:59
week        ▓▓▓▓┃──────   22%  Sat 21:00
Codex                              PRO
week        ▓───┃──────    3%  Mon 08:34
spark week  ▓───┃──────    1%  Mon 08:36
```

- **Bar** — quota consumed in that window.
- **`┃` tick** — where the bar *should* be if you spent the window evenly.
  Fill left of the tick, you are under budget; right of it, you are ahead.
- **Colour** — pace, not absolute. Green at or under the even-burn line,
  orange up to 1.5× it, red beyond that or above 90% consumed.
- **Right column** — when the window resets, as a wall-clock time.

Two front ends draw exactly that, from the same cache file:

| | [`macos/`](macos) — native app | [`python/`](python) — Übersicht widget |
| --- | --- | --- |
| Menu bar | ring + percentage, click for the card | — |
| Desktop card | yes, draggable | yes, draggable |
| Notifications | on threshold and on pace | — |
| Refresh | in-app timer | launchd agent |
| Needs | nothing but macOS 14+ | Python 3.10+, Übersicht |
| Build | `swift build` (Command Line Tools) | `pipx install` |

The native app is a superset and needs no third-party app to host it. The
Übersicht widget is kept for anyone already running Übersicht. They read and
write the same `~/.local/share/ai-usage/usage.json`, so running both is fine —
either one refreshing keeps the other current.

## The native app

```sh
cd macos
./build.sh --install
```

That compiles, wraps the binary in `AI Usage.app`, ad-hoc signs it, copies it to
`/Applications` and launches it.

**Menu bar.** A ring tinted by the window in the most trouble, labelled with its
percentage. Click it for the full card, a **Refresh** button and settings.

**Desktop card.** The same card, free-standing. Drag it anywhere; the position
is remembered per top-left corner, so it stays put when a row appears. It sits
just above the desktop icons and behind every window by default, the way the
Übersicht card did — tick *Keep card above other windows* to float it instead.
Right-click for refresh, hide and quit.

**Notifications.** One alert when a window passes your threshold, one when it is
burning faster than your pace multiple. Each fires at most once per window; the
moment a window resets, the slate is wiped and the next crossing is announced
again.

Settings live behind the gear: menu bar percentage on/off, desktop card on/off
and its level, open at login, both alert thresholds, and the refresh interval.

**Requirements:** macOS 14+, Command Line Tools (`xcode-select --install`).
Full Xcode is *not* needed — there is no `.xcodeproj`, `build.sh` assembles the
bundle by hand.

**Ad-hoc signing.** The app is signed with an ad-hoc identity, which is enough
for notifications and the login item but means the signature changes on every
rebuild. macOS may re-ask for Keychain consent after a rebuild; that is expected.

### Why not a WidgetKit widget

Because it would be strictly worse here. A widget extension runs sandboxed, so
it could read neither the Keychain nor `~/.codex/auth.json` and would need an
App Group — which needs a paid developer team — merely to see the cache the app
already writes. It would also need full Xcode to build, and it could only sit in
the widget grid. The panel above drags anywhere and needs none of that.

## The Übersicht widget

```sh
pipx install "git+https://github.com/gnibu/ai-usage-widget.git#subdirectory=python"
ai-usage install
```

`ai-usage install` deploys the widget, registers the refresh launch agent, offers
to `brew install --cask ubersicht` if needed, and does a first fetch. Übersicht's
first launch shows a Gatekeeper prompt ("app downloaded from the Internet") —
click **Open**. Drag the card anywhere; the position is remembered.

From a checkout:

```sh
git clone https://github.com/gnibu/ai-usage-widget.git
cd ai-usage-widget/python
pipx install .
ai-usage install
```

If you have switched to the native app and want the desktop card gone, run
`ai-usage uninstall` — the app keeps the cache current on its own.

### Commands

| Command | Does |
| --- | --- |
| `ai-usage` / `ai-usage fetch` | refresh from both providers, print a summary |
| `ai-usage fetch --json` | same, raw report on stdout |
| `ai-usage status` | show the cached reading and agent state, no network |
| `ai-usage install` | deploy widget + refresh launch agent |
| `ai-usage uninstall [--purge]` | remove them (`--purge` also drops cached data) |
| `ai-usage paths` | print every path the tool touches |

Force a refresh out of band:

```sh
launchctl kickstart gui/$(id -u)/io.github.ai-usage
```

## How it works

Everything hangs off one cache file, `~/.local/share/ai-usage/usage.json`
(override the directory with `AI_USAGE_DIR`):

| Piece | Lives at | Job |
| --- | --- | --- |
| `AI Usage.app` | `/Applications` | fetches on its own timer, draws the menu bar and the desktop card, posts notifications, writes the cache |
| `ai-usage fetch` | pipx venv, shim in `~/.local/bin` | same fetch, from the shell |
| `io.github.ai-usage.plist` | `~/Library/LaunchAgents/` | runs `ai-usage fetch --quiet` every 15 min (`StartInterval 900`, `RunAtLoad`) |
| `ai-usage.jsx` | `~/Library/Application Support/Übersicht/widgets/` | `cat`s the cache every 2 min and draws it |

The widget re-reads the cache more often than anything refetches, so the pace
tick, colours and reset times stay accurate between fetches. `Fetcher.swift` is
a direct port of `usage.py` and emits byte-identical JSON — keep them in step.

### Where the numbers come from

| Provider | Credential | Endpoint |
| --- | --- | --- |
| Claude | Keychain item `Claude Code-credentials` (written by Claude Code) | `GET api.anthropic.com/api/oauth/usage` |
| Codex | `~/.codex/auth.json` (written by the Codex CLI) | `GET chatgpt.com/backend-api/codex/usage` |

Both are the same first-party endpoints the CLIs themselves call, and both are
**undocumented internal APIs**. They can change shape or start rejecting
non-CLI callers without notice. That is the most likely way this breaks.

Which windows appear depends on what each API returns for your plan:

- Claude reports `five_hour` and `seven_day`.
- Codex reports a primary window, an optional secondary one, and any
  model-specific buckets from `additional_rate_limits` (e.g. GPT-5.3-Codex-Spark)
  as their own row. On Pro today only weekly windows come back — `secondary_window`
  is `null`. If a 5-hour window reappears both front ends render it with no change.

## Security

Worth understanding before running something that touches your API credentials.

**What the fetch does**

- Reads the Claude OAuth token via `/usr/bin/security` and the Codex token from
  `~/.codex/auth.json` — the two stores the CLIs already maintain.
- Sends each token *only* to its own provider's host. No third party, no
  telemetry, no analytics.
- Never prints or logs a token. The cache holds percentages, reset timestamps
  and plan names — nothing secret.
- Read-only on both credential stores. It never writes or refreshes tokens, so
  it cannot invalidate either CLI's login.
- No dependencies on either side — Python standard library, Swift standard
  frameworks. There is no supply chain to audit beyond this repo. Read it; it is
  short.

**Why the split matters**

Übersicht widgets are arbitrary shell executed on a timer — that is the app's
whole design. Rather than give a third-party app a path to your Keychain, the
widget's entire command is `cat ~/.local/share/ai-usage/usage.json`. The
privileged work happens in the launch agent (or the native app), which runs as
you. Übersicht never sees a token.

**What you are trusting**

- Übersicht: open source (MIT), signed and notarized as
  `Developer ID Application: Felix Hageloh (S3P44NRLCW)`. Verify yours:
  ```sh
  spctl -a -vv /Applications/Übersicht.app
  ```
- Anything that can write to `~/Library/Application Support/Übersicht/widgets/`
  runs code as you. Treat that directory like `~/.zshrc`.

## Troubleshooting

**Menu bar ring missing**

macOS hides status items when the bar runs out of room, and menu bar managers
(Bartender, Ice, Hidden Bar) park them off-screen by default. Check the app is
alive with `pgrep -fl "AI Usage"`, then look in your manager's hidden section.

**Desktop card missing**

By default it sits behind every window, so a maximised window hides it. Show the
desktop, or tick *Keep card above other windows*. If it was dragged to a screen
that is no longer attached, it comes back to the top right on the next launch.

**Widget blank or stale**

```sh
ai-usage status                                       # cached values + agent state
launchctl kickstart gui/$(id -u)/io.github.ai-usage   # force a fetch
cat ~/.local/share/ai-usage/error.log                 # agent stderr
```

Both front ends label a reading `(stale)` once the cache is more than 45 minutes
old.

**No notifications**

The app asks for permission on first launch. If it was refused, re-enable it
under System Settings → Notifications → AI Usage. Notifications need the app to
be signed, which `build.sh` handles — running the raw `swift build` binary
skips them on purpose.

**`token expired — run claude` / `run codex`**

The OAuth token lapsed. Start the relevant CLI once; it refreshes the token in
place and the next fetch recovers. By design this tool never refreshes tokens
itself — it will not touch your logins.

**`http 403` from Codex**

The edge in front of `chatgpt.com` intermittently rejects a valid request. The
fetch already retries once; a later run generally succeeds.

## Uninstall

```sh
osascript -e 'quit app "AI Usage"'
rm -rf "/Applications/AI Usage.app"

ai-usage uninstall --purge
pipx uninstall ai-usage-widget
brew uninstall --cask ubersicht   # optional
```

## License

MIT
