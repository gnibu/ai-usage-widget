# ai-usage-widget

A macOS menu bar app showing how much of your **Claude Code** and **Codex**
quota you have burned, and whether you are burning it faster than the window
refills. Refreshes every 15 minutes, and tells you when you are running hot.

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

## Install

```sh
git clone https://github.com/gnibu/ai-usage-widget.git
cd ai-usage-widget
./build.sh --install
```

That compiles, wraps the binary in `AI Usage.app`, ad-hoc signs it, copies it to
`/Applications` and launches it. Drop `--install` to build into `.build/` and
leave `/Applications` alone.

When upgrading from the Python/Übersicht version, `--install` unloads and
removes its launch agent and widget automatically. Übersicht itself and the
old pipx package are left installed; remove them separately if no longer used.

**Requirements:** macOS 14+, Command Line Tools (`xcode-select --install`), and
Claude Code and/or Codex already logged in. Either provider can be missing — you
get a per-provider error rather than a failure. Full Xcode is *not* needed;
there is no `.xcodeproj`, `build.sh` assembles the bundle by hand.

## What you get

**Menu bar.** The window in the most trouble, as its provider's logo, a ring
filled to its consumption and tinted by its pace, and the percentage. Any of the
three can be switched off, and you can widen it to as many as four windows,
which are simply the busiest ones — two Claude windows if Claude owns the two
busiest. Tick *Always keep every provider on screen* to hand each provider a
slot first instead, so a quiet Codex stays visible beside a loud Claude at the
cost of bumping a window that really is busier. The window's initial sits in the hole
of the ring (`w` week, `h` 5-hour, `s` spark week), which is the one place a
menu bar has room to spare. Click it for the full card, a **Refresh** button and
settings.

**Desktop card.** The same card, free-standing. Drag it anywhere; the position
is remembered by its top left corner, so it stays put when a row appears. It
sits just above the desktop icons and behind every window by default — tick
*Keep card above other windows* to float it instead. Right-click it for refresh,
hide and quit.

**Notifications.** One alert when a window passes your threshold, one when it is
burning faster than your pace multiple. Each fires at most once per window; the
moment a window resets, the slate is wiped and the next crossing is announced
again.

Settings live behind the gear: which menu bar parts to draw and how many
windows, desktop card on/off and its level, open at login, both alert
thresholds, and the refresh interval.

### Why not a WidgetKit widget

Because it would be strictly worse here. A widget extension runs sandboxed, so
it could read neither the Keychain nor `~/.codex/auth.json`, and it would need
an App Group — which needs a paid developer team — merely to see the cache the
app already writes. It would also need full Xcode to build, and it could only
sit in the widget grid. The desktop card drags anywhere and needs none of that.

## How it works

The app fetches on its own timer, on wake, and on demand, then writes
`~/.local/share/ai-usage/usage.json` (override the directory with
`AI_USAGE_DIR`). Everything on screen is drawn from that one file, so the menu
bar ring, the dropdown and the desktop card can never disagree.

| Source file | Job |
| --- | --- |
| `Fetcher.swift` | reads both credential stores, calls both usage APIs |
| `Report.swift` | the JSON written to the cache |
| `Pace.swift` | elapsed share, pace ratio, colours, reset labels |
| `UsageCard.swift` | the reading, shared by the dropdown and the desktop card |
| `StatusIcon.swift` | the menu bar item — logo, ring, percentage |
| `BrandGlyph.swift` | reads `Resources/Icons/*.svg` into drawable outlines |
| `Notifier.swift` | threshold and pace alerts, one per window instance |
| `UsageStore.swift` | the single reading, its timer, and the cache |

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
  as their own row. On Pro today only weekly windows come back —
  `secondary_window` is `null`. If a 5-hour window reappears it is rendered with
  no change.

## Security

Worth understanding before running something that touches your API credentials.

- Reads the Claude OAuth token via `/usr/bin/security` and the Codex token from
  `~/.codex/auth.json` — the two stores the CLIs already maintain.
- Sends each token *only* to its own provider's host. No third party, no
  telemetry, no analytics.
- Never prints or logs a token. The cache holds percentages, reset timestamps
  and plan names — nothing secret.
- Read-only on both credential stores. It never writes or refreshes tokens, so
  it cannot invalidate either CLI's login.
- No dependencies beyond the system frameworks. There is no supply chain to
  audit beyond this repo. Read it; it is short.

**Ad-hoc signing.** The app is signed with an ad-hoc identity, which is enough
for notifications and the login item but means the signature changes on every
rebuild. macOS may re-ask for Keychain consent after a rebuild; that is expected.

## Troubleshooting

**Menu bar shows a letter instead of a logo**

`BrandGlyph` falls back to the provider's initial when it cannot read
`Resources/Icons`. That happens when the app is run straight out of `swift
build` rather than from the bundle `build.sh` assembles. Point it at the working
copy with `AI_USAGE_ICONS=$PWD/Resources/Icons`, or just use `./build.sh`.

**Menu bar item missing**

macOS hides status items when the bar runs out of room, and menu bar managers
(Bartender, Ice, Hidden Bar) park them off-screen by default. Check the app is
alive with `pgrep -fl "AI Usage"`, then look in your manager's hidden section.

**Desktop card missing**

By default it sits behind every window, so a maximised window hides it. Show the
desktop, or tick *Keep card above other windows*. If it was dragged to a screen
that is no longer attached, it comes back to the top right on the next launch.

**No notifications**

The app asks for permission on first launch. If it was refused, re-enable it
under System Settings → Notifications → AI Usage. Notifications need the app to
be signed, which `build.sh` handles — running the raw `swift build` binary skips
them on purpose.

**`token expired — run claude` / `run codex`**

The OAuth token lapsed. Start the relevant CLI once; it refreshes the token in
place and the next fetch recovers. By design this app never refreshes tokens
itself — it will not touch your logins.

**`http 403` from Codex**

The edge in front of `chatgpt.com` intermittently rejects a valid request. The
fetch already retries once; a later run generally succeeds.

**Reading is stale**

The header marks a reading `(stale)` once the cache is more than 45 minutes old.
Hit **Refresh**; if that fails the per-provider error says why.

## Uninstall

```sh
osascript -e 'quit app "AI Usage"'
rm -rf "/Applications/AI Usage.app"
rm -rf ~/.local/share/ai-usage
defaults delete io.github.ai-usage
```

## License

Copyright © 2026 Benoit Pothier. Released under the MIT License — see
[`LICENSE`](LICENSE).

`Resources/Icons` holds the Claude and OpenAI marks, taken verbatim from
[simple-icons](https://github.com/simple-icons/simple-icons), whose packaging is
CC0. The marks themselves remain trademarks of Anthropic and OpenAI, and are
used here only to identify whose quota a row is reporting. They are drawn
monochrome and scaled uniformly, never recoloured, stretched or rotated. Neither
company endorses or is affiliated with this project.
