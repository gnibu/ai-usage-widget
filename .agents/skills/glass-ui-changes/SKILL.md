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
cliclick c:3252,15                     # centre of the item
```

- The app has no main menu, so the status item is **`menu bar 1`**, not `menu bar 2`.
  (`menu bar 2` is right for apps that also own a normal menu bar.)
- `perform action "AXPress"` does *not* open it — the button acts on mouse-up.
  Use `cliclick`.
- Screen coordinates here are 1:1 with screenshot pixels. Do not halve them for
  Retina; check with the AX position before assuming.

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
