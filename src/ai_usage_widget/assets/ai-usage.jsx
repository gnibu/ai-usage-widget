// AI usage widget — Claude Code + Codex rate limits, refreshed every 15 min.
//
// The widget only reads a plain JSON file of percentages. The privileged work
// (Keychain read, OAuth calls) is done by the io.github.ai-usage launch agent,
// so Übersicht never touches credentials.
//
// Drag the card anywhere on the desktop; the position is remembered.
// Right-click for a refresh / quit menu.

import { run } from "uebersicht";

export const command = "cat $HOME/.local/share/ai-usage/usage.json";

export const refreshFrequency = 120000; // re-read the cached file every 2 min

export const className = `
  top: 40px;
  right: 30px;
  width: 300px;
  font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;
  color: #e8e8ed;
  background: rgba(22, 22, 26, 0.72);
  backdrop-filter: blur(24px);
  border: 1px solid rgba(255, 255, 255, 0.08);
  border-radius: 14px;
  padding: 14px 16px 12px;
  box-shadow: 0 8px 28px rgba(0, 0, 0, 0.35);
  z-index: 0;

  /* required for the widget to receive mouse events in Übersicht */
  pointer-events: all;
  cursor: grab;
  user-select: none;
  -webkit-user-select: none;

  &:active { cursor: grabbing; }

  .head {
    display: flex;
    justify-content: space-between;
    align-items: baseline;
    font-size: 10px;
    letter-spacing: 0.08em;
    text-transform: uppercase;
    color: rgba(232, 232, 237, 0.45);
    margin-bottom: 10px;
  }

  .provider { margin-bottom: 12px; }
  .provider:last-child { margin-bottom: 2px; }

  .name {
    display: flex;
    justify-content: space-between;
    align-items: baseline;
    font-size: 12px;
    font-weight: 600;
    margin-bottom: 6px;
  }
  .plan {
    font-size: 9px;
    font-weight: 500;
    text-transform: uppercase;
    letter-spacing: 0.06em;
    color: rgba(232, 232, 237, 0.4);
  }

  .row {
    display: flex;
    align-items: center;
    gap: 8px;
    margin-bottom: 5px;
  }
  .label {
    width: 62px;
    font-size: 10px;
    color: rgba(232, 232, 237, 0.5);
    flex: none;
  }
  .track {
    display: block;
    position: relative;
    flex: 1;
    height: 6px;
    border-radius: 3px;
    background: rgba(255, 255, 255, 0.09);
    overflow: hidden;
  }
  .fill {
    display: block;
    height: 100%;
    border-radius: 3px;
  }
  /* where usage *should* be if spent evenly across the window */
  .pace {
    display: block;
    position: absolute;
    top: 0;
    width: 1px;
    height: 100%;
    background: rgba(255, 255, 255, 0.55);
  }
  .pct {
    width: 30px;
    text-align: right;
    font-size: 10px;
    font-variant-numeric: tabular-nums;
    flex: none;
  }
  .reset {
    width: 68px;
    text-align: right;
    font-size: 9px;
    font-variant-numeric: tabular-nums;
    color: rgba(232, 232, 237, 0.38);
    flex: none;
  }
  .err { font-size: 10px; color: #ff8a80; }

  .menu {
    position: absolute;
    min-width: 132px;
    padding: 4px;
    background: rgba(40, 40, 46, 0.96);
    backdrop-filter: blur(24px);
    border: 1px solid rgba(255, 255, 255, 0.1);
    border-radius: 8px;
    box-shadow: 0 6px 20px rgba(0, 0, 0, 0.45);
    z-index: 10;
  }
  .menu-item {
    padding: 5px 10px;
    border-radius: 5px;
    font-size: 11px;
    color: #e8e8ed;
    cursor: default;
    white-space: nowrap;
  }
  .menu-item:hover { background: rgba(255, 255, 255, 0.12); }
  .menu-item.busy { color: rgba(232, 232, 237, 0.45); }
`;

const POSITION_KEY = "ai-usage-position";
const MENU_ID = "ai-usage-menu";

const WIDGET_ID = "ai-usage-jsx";
const REFRESH_CMD =
  `launchctl kickstart -k gui/$(id -u)/io.github.ai-usage` +
  ` && osascript -e 'tell application "Übersicht" to refresh widget id "${WIDGET_ID}"'`;
const QUIT_CMD = `osascript -e 'tell application "Übersicht" to quit'`;

function closeMenu() {
  const menu = document.getElementById(MENU_ID);
  if (menu) menu.remove();
  document.removeEventListener("mousedown", onOutsideClick, true);
  document.removeEventListener("keydown", onEscape, true);
}

function onOutsideClick(event) {
  const menu = document.getElementById(MENU_ID);
  if (menu && !menu.contains(event.target)) closeMenu();
}

function onEscape(event) {
  if (event.key === "Escape") closeMenu();
}

// Built imperatively rather than through render(), which Übersicht re-runs on
// every refresh and would tear an open menu down mid-click.
const openMenu = (event) => {
  const wrapper = event.currentTarget.parentElement;
  if (!wrapper) return;
  event.preventDefault();
  closeMenu();

  const rect = wrapper.getBoundingClientRect();
  const menu = document.createElement("div");
  menu.id = MENU_ID;
  menu.className = "menu";
  menu.style.left = `${event.clientX - rect.left}px`;
  menu.style.top = `${event.clientY - rect.top}px`;

  const items = [
    {
      label: "Refresh now",
      busyLabel: "Refreshing…",
      // The agent rewrites the cache, then Übersicht re-reads it.
      command: REFRESH_CMD,
      keepOpen: true,
    },
    { label: "Quit Übersicht", command: QUIT_CMD },
  ];

  items.forEach((item) => {
    const el = document.createElement("div");
    el.className = "menu-item";
    el.textContent = item.label;
    el.addEventListener("mousedown", (e) => {
      e.stopPropagation();
      if (!item.keepOpen) {
        closeMenu();
        run(item.command);
        return;
      }
      el.textContent = item.busyLabel;
      el.classList.add("busy");
      run(item.command).then(closeMenu, closeMenu);
    });
    menu.appendChild(el);
  });

  wrapper.appendChild(menu);
  document.addEventListener("mousedown", onOutsideClick, true);
  document.addEventListener("keydown", onEscape, true);
};

// Übersicht owns the positioned wrapper element, so dragging means moving the
// widget's parent node and persisting the offset in the WebView's localStorage.
const restorePosition = (node) => {
  const wrapper = node && node.parentElement;
  if (!wrapper) return;
  let saved = null;
  try {
    saved = JSON.parse(window.localStorage.getItem(POSITION_KEY));
  } catch (e) {
    saved = null;
  }
  if (!saved) return;
  wrapper.style.right = "auto";
  wrapper.style.left = `${saved.left}px`;
  wrapper.style.top = `${saved.top}px`;
};

const startDrag = (event) => {
  const wrapper = event.currentTarget.parentElement;
  if (!wrapper || event.button !== 0) return;
  event.preventDefault();

  const rect = wrapper.getBoundingClientRect();
  const offsetX = event.clientX - rect.left;
  const offsetY = event.clientY - rect.top;
  wrapper.style.right = "auto";

  const onMove = (moveEvent) => {
    const left = Math.max(0, Math.min(window.innerWidth - rect.width, moveEvent.clientX - offsetX));
    const top = Math.max(0, Math.min(window.innerHeight - rect.height, moveEvent.clientY - offsetY));
    wrapper.style.left = `${left}px`;
    wrapper.style.top = `${top}px`;
  };

  const onUp = () => {
    document.removeEventListener("mousemove", onMove);
    document.removeEventListener("mouseup", onUp);
    try {
      window.localStorage.setItem(
        POSITION_KEY,
        JSON.stringify({
          left: parseFloat(wrapper.style.left) || 0,
          top: parseFloat(wrapper.style.top) || 0,
        })
      );
    } catch (e) {
      // localStorage unavailable — position simply won't survive a reload
    }
  };

  document.addEventListener("mousemove", onMove);
  document.addEventListener("mouseup", onUp);
};

// Share of the window already elapsed, 0-100. Null when the window length or
// reset time is unknown, in which case we fall back to absolute thresholds.
const elapsedPercent = (w) => {
  if (!w.resets_at || !w.window_seconds) return null;
  const remaining = w.resets_at - Date.now() / 1000;
  const elapsed = w.window_seconds - remaining;
  return Math.max(0, Math.min(100, (elapsed / w.window_seconds) * 100));
};

// Green while spending is at or under the even-burn pace, orange when running
// ahead of it, red when far ahead or nearly exhausted.
const barColor = (pct, elapsed) => {
  if (pct >= 90) return "#ff6b6b";
  if (elapsed === null || elapsed < 5) {
    // Too early in the window for a pace ratio to mean anything.
    if (pct >= 60) return "#ff6b6b";
    if (pct >= 30) return "#ffb454";
    return "#5ec98a";
  }
  const ratio = pct / elapsed;
  if (ratio > 1.5) return "#ff6b6b";
  if (ratio > 1.0) return "#ffb454";
  return "#5ec98a";
};

const WEEKDAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

const clock = (date) =>
  `${String(date.getHours()).padStart(2, "0")}:${String(date.getMinutes()).padStart(2, "0")}`;

// Absolute reset time. Bare clock today, weekday within the week, and a date
// beyond that — a weekday alone would be ambiguous once it wraps around.
const resetLabel = (epoch) => {
  // An untouched window has no reset instant yet — the clock starts on first use.
  if (!epoch) return "idle";
  const at = new Date(epoch * 1000);
  const now = new Date();
  if (at <= now) return "now";
  if (at.toDateString() === now.toDateString()) return clock(at);
  const days = (at - now) / 86400000;
  if (days >= 6) return `${MONTHS[at.getMonth()]} ${at.getDate()} ${clock(at)}`;
  return `${WEEKDAYS[at.getDay()]} ${clock(at)}`;
};

export const render = ({ output, error }) => {
  let body;

  if (error) {
    body = <div className="err">widget error: {String(error)}</div>;
  } else {
    let data = null;
    try {
      data = JSON.parse(output);
    } catch (e) {
      data = null;
    }

    if (!data) {
      body = <div className="err">no data yet</div>;
    } else {
      const stale = Date.now() / 1000 - data.updated_at > 2700;
      body = (
        <div>
          <div className="head">
            <span>AI usage</span>
            <span>{stale ? `${data.updated_label} (stale)` : data.updated_label}</span>
          </div>

          {data.providers.map((p) => (
            <div className="provider" key={p.name}>
              <div className="name">
                <span>{p.name}</span>
                <span className="plan">{p.plan || ""}</span>
              </div>

              {p.ok ? (
                p.windows.map((w) => {
                  const elapsed = elapsedPercent(w);
                  return (
                    <div className="row" key={w.label}>
                      <span className="label">{w.label}</span>
                      <span className="track">
                        <span
                          className="fill"
                          style={{
                            width: `${Math.min(100, Math.max(2, w.percent))}%`,
                            background: barColor(w.percent, elapsed),
                          }}
                        />
                        {elapsed === null ? null : (
                          <span className="pace" style={{ left: `${elapsed}%` }} />
                        )}
                      </span>
                      <span className="pct">{Math.round(w.percent)}%</span>
                      <span className="reset">{resetLabel(w.resets_at)}</span>
                    </div>
                  );
                })
              ) : (
                <div className="err">{p.error || "unavailable"}</div>
              )}
            </div>
          ))}
        </div>
      );
    }
  }

  return (
    <div ref={restorePosition} onMouseDown={startDrag} onContextMenu={openMenu}>
      {body}
    </div>
  );
};
