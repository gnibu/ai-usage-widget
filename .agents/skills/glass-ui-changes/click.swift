// Click at an exact point in global display coordinates — the same space the
// accessibility API reports positions in.
//
// This exists because cliclick does not agree with that space once a display
// sits at negative y. Measured on a two-display layout (external 2560x1440 at
// y -1440..0, built-in Retina below it at y 0..1117):
//
//     cliclick m:1687,-1425   ->  cliclick p  ->  1687,-2332
//     /tmp/click 1687 -1425   ->  cliclick p  ->  1687,-1425
//
// 907 points off, silently, so the click lands on nothing and the panel never
// opens. CGEvent takes the AX coordinates verbatim.
//
//     swiftc -O click.swift -o /tmp/click
//     /tmp/click <x> <y>

import CoreGraphics
import Foundation

let args = CommandLine.arguments
guard args.count == 3, let x = Double(args[1]), let y = Double(args[2]) else {
    FileHandle.standardError.write("usage: click <x> <y>\n".data(using: .utf8)!)
    exit(2)
}

let point = CGPoint(x: x, y: y)
let source = CGEventSource(stateID: .hidSystemState)

// Move first. The status item tracks the cursor, and a down event arriving at a
// point the cursor has never visited is not always routed to it.
CGEvent(mouseEventSource: source, mouseType: .mouseMoved,
        mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
usleep(120_000)

// The button acts on mouse-up, which is why AXPress does nothing here.
CGEvent(mouseEventSource: source, mouseType: .leftMouseDown,
        mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
usleep(60_000)
CGEvent(mouseEventSource: source, mouseType: .leftMouseUp,
        mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
