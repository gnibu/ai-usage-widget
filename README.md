# ai-usage-widget

A macOS desktop widget showing how much of your **Claude Code** and **Codex**
quota you have burned, and whether you are burning it faster than the window
refills. Refreshes hourly.

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

Drag the card anywhere; the position is remembered.

## Install

```sh
pipx install git+https://github.com/gnibu/ai-usage-widget.git
ai-usage install
```

`ai-usage install` deploys the widget, registers an hourly launch agent, offers
to `brew install --cask ubersicht` if needed, and does a first fetch. Übersicht's
first launch shows a Gatekeeper prompt ("app downloaded from the Internet") —
click **Open**.

From a checkout:

```sh
git clone https://github.com/gnibu/ai-usage-widget.git
cd ai-usage-widget
pipx install .
ai-usage install
```

### Requirements

- macOS
- Python 3.10+
- [Übersicht](https://tracesof.net/uebersicht/) (the installer can fetch it)
- Claude Code and/or Codex already logged in. Either can be missing — the widget
  shows a per-provider error instead of failing.

## Commands

| Command | Does |
| --- | --- |
| `ai-usage` / `ai-usage fetch` | refresh from both providers, print a summary |
| `ai-usage fetch --json` | same, raw report on stdout |
| `ai-usage status` | show the cached reading and agent state, no network |
| `ai-usage install` | deploy widget + hourly launch agent |
| `ai-usage uninstall [--purge]` | remove them (`--purge` also drops cached data) |
| `ai-usage paths` | print every path the tool touches |

Force a refresh out of band:

```sh
launchctl kickstart gui/$(id -u)/io.github.ai-usage
```

## How it works

Three pieces, deliberately split so the desktop widget never handles credentials:

| Piece | Lives at | Job |
| --- | --- | --- |
| `ai-usage fetch` | pipx venv, shim in `~/.local/bin` | reads tokens, calls both usage APIs, writes the cache |
| `io.github.ai-usage.plist` | `~/Library/LaunchAgents/` | runs `ai-usage fetch --quiet` hourly (`StartInterval 3600`, `RunAtLoad`) |
| `ai-usage.jsx` | `~/Library/Application Support/Übersicht/widgets/` | `cat`s the cache every 5 min and draws it |

The cache is `~/.local/share/ai-usage/usage.json` (override the directory with
`AI_USAGE_DIR`). The widget re-reads it more often than the agent refetches, so
the pace tick, colours and reset times stay accurate between fetches.

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
  is `null`. If a 5-hour window reappears the widget renders it with no change.

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
- Standard library only — zero dependencies, so there is no supply chain to
  audit beyond `src/ai_usage_widget/`. Read it; it is short.

**Why the split matters**

Übersicht widgets are arbitrary shell executed on a timer — that is the app's
whole design. Rather than give a third-party app a path to your Keychain, the
widget's entire command is `cat ~/.local/share/ai-usage/usage.json`. The
privileged work happens in the launch agent, which runs as you. Übersicht never
sees a token.

**What you are trusting**

- Übersicht: open source (MIT), signed and notarized as
  `Developer ID Application: Felix Hageloh (S3P44NRLCW)`. Verify yours:
  ```sh
  spctl -a -vv /Applications/Übersicht.app
  ```
- Anything that can write to `~/Library/Application Support/Übersicht/widgets/`
  runs code as you. Treat that directory like `~/.zshrc`.

## Troubleshooting

**Widget blank or stale**

```sh
ai-usage status                                       # cached values + agent state
launchctl kickstart gui/$(id -u)/io.github.ai-usage   # force a fetch
cat ~/.local/share/ai-usage/error.log                 # agent stderr
```

Then Refresh from Übersicht's menu bar icon. The widget header shows `(stale)`
once the cache is more than two hours old.

**`token expired — run claude` / `run codex`**

The OAuth token lapsed. Start the relevant CLI once; it refreshes the token in
place and the next fetch recovers. By design this tool never refreshes tokens
itself — it will not touch your logins.

**`http 403` from Codex**

The edge in front of `chatgpt.com` intermittently rejects a valid request. The
fetch already retries once; a later run generally succeeds.

## Uninstall

```sh
ai-usage uninstall --purge
pipx uninstall ai-usage-widget
brew uninstall --cask ubersicht   # optional
```

## License

MIT
