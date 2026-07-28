"""Command line entry point: `ai-usage [fetch|install|uninstall|status|paths]`.

`install` is deliberately the only privileged-looking step, and even it only
copies files and registers a launch agent — the widget it deploys never reads
credentials, it reads the JSON cache this CLI writes.
"""

from __future__ import annotations

import argparse
import json
import os
import plistlib
import shutil
import subprocess
import sys
import time
from importlib import resources
from typing import Any

from . import usage

LABEL = "io.github.ai-usage"
LEGACY_LABELS = ("net.niak.ai-usage",)

WIDGET_DIR = os.path.expanduser("~/Library/Application Support/Übersicht/widgets")
WIDGET_PATH = os.path.join(WIDGET_DIR, "ai-usage.jsx")
AGENT_DIR = os.path.expanduser("~/Library/LaunchAgents")
AGENT_PATH = os.path.join(AGENT_DIR, f"{LABEL}.plist")
UBERSICHT_APP = "/Applications/Übersicht.app"

REFRESH_SECONDS = 900


# --------------------------------------------------------------------------- #
# helpers
# --------------------------------------------------------------------------- #

def _say(message: str) -> None:
    print(f"  {message}")


def _fail(message: str) -> int:
    print(f"error: {message}", file=sys.stderr)
    return 1


def _asset(name: str) -> str:
    return resources.files("ai_usage_widget.assets").joinpath(name).read_text()


def _launchctl(*args: str) -> subprocess.CompletedProcess[bytes]:
    return subprocess.run(["launchctl", *args], capture_output=True)


def _domain() -> str:
    return f"gui/{os.getuid()}"


def _format_report(report: dict[str, Any]) -> str:
    lines = []
    for provider in report["providers"]:
        if provider["ok"]:
            bits = "  ".join(
                f"{w['label']} {round(w['percent'])}%" for w in provider["windows"]
            )
            lines.append(f"  {provider['name']:<8} {provider.get('plan') or '':<5} {bits}")
        else:
            lines.append(f"  {provider['name']:<8} {provider.get('error')}")
    return "\n".join(lines)


# --------------------------------------------------------------------------- #
# commands
# --------------------------------------------------------------------------- #

def cmd_fetch(args: argparse.Namespace) -> int:
    """Refresh the cache. This is what the launch agent runs on its interval."""
    report = usage.write_report()
    if args.quiet:
        return 0
    print(json.dumps(report) if args.json else _format_report(report))
    return 0


def cmd_status(_: argparse.Namespace) -> int:
    """Show the cached reading without hitting the network."""
    try:
        with open(usage.CACHE_PATH) as handle:
            report = json.load(handle)
    except (OSError, ValueError):
        return _fail(f"no cached data at {usage.CACHE_PATH} — run `ai-usage fetch`")

    age = int(time.time()) - int(report.get("updated_at", 0))
    print(f"  updated  {report.get('updated_label')} ({age // 60} min ago)")
    print(_format_report(report))

    loaded = _launchctl("print", f"{_domain()}/{LABEL}").returncode == 0
    print(f"  agent    {'loaded' if loaded else 'not loaded — run `ai-usage install`'}")
    return 0


def cmd_paths(_: argparse.Namespace) -> int:
    for name, path in (
        ("cache", usage.CACHE_PATH),
        ("widget", WIDGET_PATH),
        ("agent", AGENT_PATH),
        ("errors", os.path.join(usage.STATE_DIR, "error.log")),
    ):
        print(f"  {name:<8} {path}")
    return 0


def cmd_install(args: argparse.Namespace) -> int:
    if sys.platform != "darwin":
        return _fail("macOS only (needs Keychain, launchd and Übersicht)")

    if not os.path.isdir(UBERSICHT_APP):
        if args.yes or _prompt_yes("Übersicht is not installed. Install it with Homebrew?"):
            if not shutil.which("brew"):
                return _fail("Homebrew not found — install Übersicht from tracesof.net/uebersicht")
            subprocess.run(["brew", "install", "--cask", "ubersicht"], check=True)
        else:
            return _fail("Übersicht is required: brew install --cask ubersicht")

    os.makedirs(WIDGET_DIR, exist_ok=True)
    os.makedirs(AGENT_DIR, exist_ok=True)
    os.makedirs(usage.STATE_DIR, exist_ok=True)

    with open(WIDGET_PATH, "w") as handle:
        handle.write(_asset("ai-usage.jsx"))
    _say(f"widget   {WIDGET_PATH}")

    # Point the agent at this very console script, so it uses the same
    # interpreter pipx (or pip, or a venv) already resolved for us.
    program = os.path.abspath(sys.argv[0])
    plist: dict[str, Any] = {
        "Label": LABEL,
        "ProgramArguments": [program, "fetch", "--quiet"],
        "StartInterval": REFRESH_SECONDS,
        "RunAtLoad": True,
        "StandardOutPath": "/dev/null",
        "StandardErrorPath": os.path.join(usage.STATE_DIR, "error.log"),
    }
    with open(AGENT_PATH, "wb") as binary:
        plistlib.dump(plist, binary)
    _say(f"agent    {AGENT_PATH}")
    _say(f"command  {program} fetch")

    for label in (*LEGACY_LABELS, LABEL):
        _launchctl("bootout", f"{_domain()}/{label}")
        if label in LEGACY_LABELS:
            legacy_plist = os.path.join(AGENT_DIR, f"{label}.plist")
            if os.path.exists(legacy_plist):
                os.remove(legacy_plist)
                _say(f"removed  {legacy_plist} (superseded)")

    result = _launchctl("bootstrap", _domain(), AGENT_PATH)
    if result.returncode != 0:
        return _fail(f"launchctl bootstrap failed: {result.stderr.decode().strip()}")

    print()
    print(_format_report(usage.write_report()))
    print()

    subprocess.run(["open", "-a", UBERSICHT_APP], capture_output=True)
    print(
        "Installed. The widget appears top-right of the desktop; drag it anywhere.\n"
        "\n"
        f"  refresh now   launchctl kickstart {_domain()}/{LABEL}\n"
        "  cached data   ai-usage status\n"
        "  remove        ai-usage uninstall\n"
        "\n"
        "Übersicht's first launch shows a Gatekeeper prompt — click Open."
    )
    return 0


def cmd_uninstall(args: argparse.Namespace) -> int:
    for label in (*LEGACY_LABELS, LABEL):
        _launchctl("bootout", f"{_domain()}/{label}")
        path = os.path.join(AGENT_DIR, f"{label}.plist")
        if os.path.exists(path):
            os.remove(path)
            _say(f"removed  {path}")

    if os.path.exists(WIDGET_PATH):
        os.remove(WIDGET_PATH)
        _say(f"removed  {WIDGET_PATH}")

    if args.purge and os.path.isdir(usage.STATE_DIR):
        shutil.rmtree(usage.STATE_DIR)
        _say(f"removed  {usage.STATE_DIR}")

    print(
        "\nThe launch agent and widget are gone."
        + ("" if args.purge else f"\nCached data kept in {usage.STATE_DIR} (--purge to delete).")
        + "\nÜbersicht itself was left installed: brew uninstall --cask ubersicht"
        + "\nThis CLI: pipx uninstall ai-usage-widget"
    )
    return 0


def _prompt_yes(question: str) -> bool:
    try:
        return input(f"{question} [y/N] ").strip().lower().startswith("y")
    except EOFError:
        return False


# --------------------------------------------------------------------------- #

def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="ai-usage",
        description="Claude Code and Codex rate-limit usage, on your macOS desktop.",
    )
    sub = parser.add_subparsers(dest="command")

    fetch = sub.add_parser("fetch", help="refresh usage from both providers (default)")
    fetch.add_argument("--json", action="store_true", help="print the raw report")
    fetch.add_argument("--quiet", action="store_true", help="write the cache, print nothing")
    fetch.set_defaults(func=cmd_fetch)

    status = sub.add_parser("status", help="show the cached reading, no network")
    status.set_defaults(func=cmd_status)

    install = sub.add_parser("install", help="deploy the widget and its refresh agent")
    install.add_argument("-y", "--yes", action="store_true", help="assume yes to prompts")
    install.set_defaults(func=cmd_install)

    uninstall = sub.add_parser("uninstall", help="remove the widget and launch agent")
    uninstall.add_argument("--purge", action="store_true", help="also delete cached data")
    uninstall.set_defaults(func=cmd_uninstall)

    paths = sub.add_parser("paths", help="print every path this tool touches")
    paths.set_defaults(func=cmd_paths)

    args = parser.parse_args(argv)
    if not getattr(args, "command", None):
        args = parser.parse_args(["fetch", *(argv or [])])
    func: Any = args.func
    return int(func(args))


if __name__ == "__main__":
    raise SystemExit(main())
