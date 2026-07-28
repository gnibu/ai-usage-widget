"""Fetch Claude Code and Codex rate-limit usage and emit a compact JSON report.

Reads OAuth credentials already stored on the machine by the two CLIs:
  - Claude Code: macOS Keychain item "Claude Code-credentials"
  - Codex:       ~/.codex/auth.json

Nothing is written back to those stores and no token is ever printed. The
report is cached on disk so the widget can fall back to the last good reading.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request
from dataclasses import asdict, dataclass, field
from datetime import datetime
from typing import Any

# The widget reads this file; keep it at a fixed location so the script can be
# run from anywhere (a git checkout, the install dir) without moving the cache.
STATE_DIR = os.environ.get("AI_USAGE_DIR") or os.path.expanduser("~/.local/share/ai-usage")
CACHE_PATH = os.path.join(STATE_DIR, "usage.json")

KEYCHAIN_SERVICE = "Claude Code-credentials"
CLAUDE_USAGE_URL = "https://api.anthropic.com/api/oauth/usage"
CODEX_AUTH_PATH = os.path.expanduser("~/.codex/auth.json")
CODEX_USAGE_URL = "https://chatgpt.com/backend-api/codex/usage"
CODEX_USER_AGENT = "codex_cli_rs/0.56.0 (Mac OS 26.4.0; arm64) Terminal"

TIMEOUT = 20


@dataclass
class Window:
    """One rate-limit window (a 5 hour session bucket, a weekly bucket, ...)."""

    label: str
    percent: float
    resets_at: int | None = None  # unix seconds
    window_seconds: int | None = None  # full length of the window


@dataclass
class Provider:
    name: str
    ok: bool = False
    plan: str | None = None
    error: str | None = None
    windows: list[Window] = field(default_factory=list)


def _get_json(url: str, headers: dict[str, str]) -> Any:
    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
        return json.loads(resp.read().decode())


def _iso_to_epoch(value: str | None) -> int | None:
    if not value:
        return None
    try:
        return int(datetime.fromisoformat(value).timestamp())
    except ValueError:
        return None


def _window_label(seconds: int | None) -> str:
    if not seconds:
        return "limit"
    if seconds >= 7 * 86400:
        return "week"
    if seconds >= 86400:
        return f"{seconds // 86400}d"
    return f"{seconds // 3600}h"


# --------------------------------------------------------------------------- #
# Claude Code
# --------------------------------------------------------------------------- #

def fetch_claude() -> Provider:
    provider = Provider(name="Claude")
    try:
        raw = subprocess.run(
            ["security", "find-generic-password", "-s", KEYCHAIN_SERVICE, "-w"],
            capture_output=True,
            text=True,
            timeout=15,
        )
        if raw.returncode != 0:
            provider.error = "keychain unavailable"
            return provider
        oauth = json.loads(raw.stdout).get("claudeAiOauth") or {}
        token = oauth.get("accessToken")
        if not token:
            provider.error = "not logged in"
            return provider
        provider.plan = oauth.get("subscriptionType")

        data = _get_json(
            CLAUDE_USAGE_URL,
            {
                "Authorization": f"Bearer {token}",
                "anthropic-beta": "oauth-2025-04-20",
                "Accept": "application/json",
            },
        )
    except urllib.error.HTTPError as exc:
        provider.error = "token expired — run claude" if exc.code == 401 else f"http {exc.code}"
        return provider
    except Exception as exc:  # network down, malformed keychain blob, ...
        provider.error = str(exc)[:80]
        return provider

    # The endpoint reports the bucket but not its length, and both are fixed.
    for key, label, length in (("five_hour", "5h", 5 * 3600), ("seven_day", "week", 7 * 86400)):
        block = data.get(key)
        if not isinstance(block, dict):
            continue
        provider.windows.append(
            Window(
                label=label,
                percent=float(block.get("utilization") or 0.0),
                resets_at=_iso_to_epoch(block.get("resets_at")),
                window_seconds=length,
            )
        )
    provider.ok = bool(provider.windows)
    if not provider.ok:
        provider.error = "no limit data"
    return provider


# --------------------------------------------------------------------------- #
# Codex
# --------------------------------------------------------------------------- #

def _codex_windows(limits: Any, prefix: str = "") -> list[Window]:
    """Turn one Codex rate_limit block into Window rows, oldest reset first."""
    if not isinstance(limits, dict):
        return []
    out: list[Window] = []
    for key in ("primary_window", "secondary_window"):
        block = limits.get(key)
        if not isinstance(block, dict):
            continue
        length = block.get("limit_window_seconds")
        out.append(
            Window(
                label=f"{prefix}{_window_label(length)}",
                percent=float(block.get("used_percent") or 0.0),
                resets_at=block.get("reset_at"),
                window_seconds=int(length) if length else None,
            )
        )
    out.sort(key=lambda w: w.window_seconds or 0)
    return out


def fetch_codex() -> Provider:
    provider = Provider(name="Codex")
    try:
        with open(CODEX_AUTH_PATH) as handle:
            tokens = json.load(handle).get("tokens") or {}
        token = tokens.get("access_token")
        if not token:
            provider.error = "not logged in"
            return provider

        headers = {
            "Authorization": f"Bearer {token}",
            "chatgpt-account-id": tokens.get("account_id") or "",
            "originator": "codex_cli_rs",
            "User-Agent": CODEX_USER_AGENT,
            "Accept": "application/json",
        }
        # The edge in front of chatgpt.com occasionally answers 403 to an
        # otherwise valid request; one retry clears it.
        try:
            data = _get_json(CODEX_USAGE_URL, headers)
        except urllib.error.HTTPError as exc:
            if exc.code != 403:
                raise
            time.sleep(2)
            data = _get_json(CODEX_USAGE_URL, headers)
    except FileNotFoundError:
        provider.error = "not logged in"
        return provider
    except urllib.error.HTTPError as exc:
        provider.error = "token expired — run codex" if exc.code == 401 else f"http {exc.code}"
        return provider
    except Exception as exc:
        provider.error = str(exc)[:80]
        return provider

    provider.plan = data.get("plan_type")
    provider.windows.extend(_codex_windows(data.get("rate_limit"), prefix=""))

    # Model-specific buckets (e.g. GPT-5.3-Codex-Spark) live in their own list
    # and are billed separately from the main quota.
    for extra in data.get("additional_rate_limits") or []:
        if not isinstance(extra, dict):
            continue
        name = str(extra.get("limit_name") or "extra")
        short = name.rsplit("-", 1)[-1].lower()
        provider.windows.extend(_codex_windows(extra.get("rate_limit"), prefix=f"{short} "))

    provider.ok = bool(provider.windows)
    if not provider.ok:
        provider.error = "no limit data"
    return provider


# --------------------------------------------------------------------------- #

def build_report() -> dict[str, Any]:
    providers = [fetch_claude(), fetch_codex()]
    return {
        "updated_at": int(time.time()),
        "updated_label": datetime.now().strftime("%H:%M"),
        "providers": [asdict(p) for p in providers],
    }


def write_report() -> dict[str, Any]:
    """Fetch, persist to the cache the widget reads, and return the report."""
    report = build_report()
    try:
        os.makedirs(STATE_DIR, exist_ok=True)
        tmp = CACHE_PATH + ".tmp"
        with open(tmp, "w") as handle:
            handle.write(json.dumps(report))
        os.replace(tmp, CACHE_PATH)
    except OSError:
        pass  # cache is a convenience, never fatal
    return report
