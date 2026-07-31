---
name: glass-ui-changes
description: How to change and verify the look of this app — the desktop card, the menu bar dropdown, the glass panes, borders, rims and the menu bar icon. Use whenever a task touches Glass.swift, PanelView.swift, DesktopCard.swift, UsageCard.swift, MenuBarItem.swift or StatusIcon.swift, or whenever someone says an edge, colour, shadow or border "looks off". Covers the pixel-measurement loop that has to back any claim about why something renders the way it does.
---

# Changing how the glass looks

The card and the dropdown are one design language rendered by two windows. Their
edges, sheen and tint are tuned against measured pixel values, not against
adjectives. This skill is the loop that produced those numbers.

## The rule

**Never write a causal claim you have not measured.** Not in a comment, not in a
commit message, not in a reply to the user.

This exists because it was broken. A hairline on the dropdown was attributed to
"our rim stacking on the system's", and the fix was to zero our own rim
(`711fc03`). The stated cause was wrong, the fix changed nothing visible, and
the wrong explanation was then baked into a comment where the next reader
inherited it. The real cause — SwiftUI compositing its own hairline *above*
hosted content — took ten minutes to establish once anyone actually sampled a
pixel.

Adjectives that must trigger measurement before you touch code: whiter, brighter,
washed out, too dark, off, doesn't match, pops too much.

## The loop

### 1. Get the change on screen

Dev builds are unreliable for this. A second copy of the app gets a status item
the window server parks off-screen when the menu bar is crowded — its panel
opens at a negative x and no screenshot will ever contain it. Install and drive
the real app:

```sh
swift build && ./build.sh --install    # relaunches /Applications/Tokens on Track.app
```

### 2. Open the dropdown without a human

```sh
PID=$(pgrep -f "/Applications/Tokens on Track.app")
osascript -e "tell application \"System Events\" to tell (first process whose unix id is $PID) to get {position, size} of menu bar item 1 of menu bar 1"
# -> 3179, 3, 147, 24   (x, y, w, h)
swiftc -O .agents/skills/glass-ui-changes/click.swift -o /tmp/click
/tmp/click 3252 15                     # centre of the item
```

- The app has no main menu, so the status item is **`menu bar 1`**, not `menu bar 2`.
  (`menu bar 2` is right for apps that also own a normal menu bar.)
- `perform action "AXPress"` does *not* open it — the button acts on mouse-up.
- **Do not use `cliclick` for this.** It disagrees with the accessibility
  coordinate space once a display sits at negative y, and it fails silently —
  the cursor lands somewhere else and the panel simply never opens. Measured on
  external-above-built-in:

  ```
  cliclick m:1687,-1425   ->  cliclick p  ->  1687,-2332    907 off
  /tmp/click 1687 -1425   ->  cliclick p  ->  1687,-1425    exact
  ```

  `click.swift` in this directory posts a CGEvent at the AX coordinates
  verbatim. `cliclick p` is still the right way to *read* the cursor back.
- Screen coordinates are points; screenshot pixels depend on which display the
  window is on. Check, do not assume — a built-in Retina panel is 2x while an
  external 1440p one is 1x, and a two-display setup hands you both at once.
- **The screen must be unlocked.** Behind the lock screen the app keeps running
  and AX keeps reporting the status item's position, so the failure presents as
  "the click did nothing" rather than "the machine is locked", and every capture
  comes back as blurred wallpaper. Check with `screencapture -x -D1` before
  debugging the click, and run captures under `caffeinate -u -t 900`.

Confirm what opened, and get its exact frame:

```sh
osascript -e "tell application \"System Events\" to tell (first process whose unix id is $PID) to get {position, size} of every window"
# positions first, then sizes: dropdown is 430x333, card is 460x283
```

### 3. Sample the pixels

`screencapture -x -t png /tmp/shot.png`, then read actual values with
`pixel.swift` in this skill directory:

```sh
swiftc .agents/skills/glass-ui-changes/pixel.swift -o /tmp/px
/tmp/px /tmp/shot.png <y> <x0> <x1>     # prints rgb + luminance per column
```

Scan across the edge you care about, starting a few pixels outside the window
frame. A border is one column; interior and backdrop are the columns either
side. Quote all three when you report.

### 4. Bisect with an absurd value

When you cannot tell whose pixel it is, make yours unmistakable — 3pt, pure red —
install, and sample. The answer is in the blend:

- Red, clean → it is yours, and it lands where you think.
- Red with white composited **on top** → something above you draws it, and no
  change inside the view tree can cover it.
- No red at the edge at all → your stroke is not where you think it is (check
  `strokeBorder`'s inward inset and the corner radius).

That single test is what settled the hairline. Reach for it early; it is cheaper
than an argument.

## Capturing for the README

`capture.sh` in this directory does the pass. Two things it cannot do for you:

- **An unfocused window lies about its controls.** Captured off-screen, the
  Settings tab came back with every toggle rendered grey — SwiftUI draws the
  inactive state, so a capture of a non-key window shows switches as off when
  they are on. Anything with a control in it has to be photographed while the
  panel is key, which means nobody may touch the machine mid-run.
- **Translucency is backdrop-dependent.** `screencapture -l` reads the window's
  own buffer and yields a neutral grey pane; a screen crop includes whatever the
  glass is sampling and yields the real material. Neither is wrong, but the two
  cannot be mixed in one set — the tints do not match. Pick per audience: `-l`
  for the README, where reproducibility wins, and a crop over a chosen backdrop
  when the glass itself is the point.

## Facts already established

Do not re-derive these, and do not undo them.

- **`MenuBarExtra(.window)` is unusable for this design.** Its window draws a
  ~white-0.6 hairline over the content it hosts. It cannot be removed, covered or
  dimmed from inside the view tree. The dropdown is therefore an app-owned
  borderless `NSPanel` (`MenuBarItem.swift`), the same way the card is
  (`DesktopCard.swift`). Do not go back to `MenuBarExtra`.
- **The panel and the card both draw their own rim** via `glassPane`. The panel's
  edge measures ~109 luminance over a ~51 interior; the card's ~161 over ~128.
  Same white rim — the dropdown's simply sits on a darker pane (`dim: 0.75`), so
  the contrast ratio is higher. If it is asked to be softer, scale `border` on
  the panel's `glassPane`; do not touch `Glass.rim`, which the card shares.
- **Shadows are the window's**, never SwiftUI's — pass `shadow: false` to
  `glassPane` in anything hosted in a panel. A SwiftUI shadow is clipped by the
  window it is drawn inside.
- **A dumped layer tree is evidence.** An `NSViewRepresentable` that walks
  `window.contentView?.superview` and prints each layer's `borderWidth`,
  `borderColor` and `backgroundColor` will tell you the alpha of your own stroke,
  which is usually enough to exonerate it. Delete the probe before committing.

## Provider marks

The Claude and OpenAI outlines in `Resources/Icons` are parsed once by
`BrandGlyph` and shared by the menu bar (`StatusIcon`), the card and the
dropdown (`BrandMark` in `UsageCard.swift`). AppKit's y runs up and SwiftUI's
runs down, which is what `path(for:fitting:flipped:)` is for — a mark that comes
out upside down is a flip argument, not a broken SVG.

They stay monochrome and uniformly scaled. Never tint them with pace colour,
stretch them or rotate them; the marks are trademarks and the colour belongs on
the ring and the track beside them.

## Before you report

- Screenshot the result and look at it.
- Quote the numbers you measured, not your reasoning about them.
- Say plainly what you could not verify. An unverified surface is a caveat, not
  a rounding error.
