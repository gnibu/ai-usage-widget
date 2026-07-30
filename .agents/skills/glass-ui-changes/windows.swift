// List the on-screen windows owned by a pid, as
//
//     <windowID> <x> <y> <width> <height> layer=<n> onscreen=<bool>
//
// The window id is what `screencapture -l` wants. Capturing by id instead of by
// region is the difference between photographing the app and photographing
// whatever happens to be in front of it.
//
// The geometry is here because the accessibility API cannot be trusted for it.
// With the dropdown open, `every window` has been observed returning both
// windows on one call and only the desktop card on the next — so `window 1`
// silently becomes the card, and a click computed from its origin lands on
// another display. CGWindowListCopyWindowInfo lists the panel every time.
// Its bounds share the AX global space: origin top-left of the main display,
// y increasing downward, so the two are interchangeable when AX does answer.
//
// Note the filter: `.optionAll`, not `.optionOnScreenOnly` with
// `.excludeDesktopElements`. The desktop card lives at a large negative window
// level so that it sits behind ordinary windows, and that combination drops it
// from the list entirely.
//
//     swiftc -O windows.swift -o /tmp/wins
//     /tmp/wins $(pgrep -f "/Applications/Tokens on Track.app")
//     2033310 1615 -1408 430 333 layer=101 onscreen=true            <- dropdown
//     2033009 395 101 460 297 layer=-2147483602 onscreen=true       <- card

import CoreGraphics
import Foundation

guard CommandLine.arguments.count == 2, let pid = Int32(CommandLine.arguments[1]) else {
    FileHandle.standardError.write("usage: windows <pid>\n".data(using: .utf8)!)
    exit(2)
}

let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []

for window in list {
    guard window[kCGWindowOwnerPID as String] as? Int32 == pid,
          let id = window[kCGWindowNumber as String] as? Int,
          let bounds = window[kCGWindowBounds as String] as? [String: Any],
          let x = bounds["X"] as? Int,
          let y = bounds["Y"] as? Int,
          let width = bounds["Width"] as? Int,
          let height = bounds["Height"] as? Int
    else { continue }

    let layer = (window[kCGWindowLayer as String] as? Int) ?? 0
    let onscreen = (window[kCGWindowIsOnscreen as String] as? Bool) ?? false
    print("\(id) \(x) \(y) \(width) \(height) layer=\(layer) onscreen=\(onscreen)")
}
