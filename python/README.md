# ai-usage-widget (Python / Übersicht)

The Übersicht flavour of [ai-usage-widget](https://github.com/gnibu/ai-usage-widget):
a `ai-usage` CLI that reads Claude Code and Codex rate limits and a launch agent
that refreshes them into `~/.local/share/ai-usage/usage.json`, which the bundled
Übersicht widget draws on the desktop.

```sh
pipx install "git+https://github.com/gnibu/ai-usage-widget.git#subdirectory=python"
ai-usage install
```

The native menu bar app lives in [`../macos`](../macos) and reads and writes the
same cache file, so the two can run side by side.

See the [top-level README](../README.md) for the full description.
