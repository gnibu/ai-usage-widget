import AppKit

// Prints the colour of one horizontal run of pixels from a screenshot, so a
// claim about an edge can be checked instead of argued.
//
//   swiftc pixel.swift -o /tmp/px
//   /tmp/px /tmp/shot.png 200 3176 3188
//
// Arguments: <image> <y> <x0> <x1>, in image pixels with the origin top left.
// Split the luminance maths across lines — as one expression the type checker
// gives up on it.

guard CommandLine.arguments.count == 5 else {
    print("usage: px <image> <y> <x0> <x1>")
    exit(2)
}

let url = URL(fileURLWithPath: CommandLine.arguments[1])
guard let y = Int(CommandLine.arguments[2]),
      let x0 = Int(CommandLine.arguments[3]),
      let x1 = Int(CommandLine.arguments[4]),
      x0 <= x1
else {
    print("y, x0 and x1 must be integers, and x0 <= x1")
    exit(2)
}

guard let image = NSImage(contentsOf: url),
      let bitmap = image.representations.first as? NSBitmapImageRep
else {
    print("could not read \(url.path)")
    exit(1)
}

for x in x0...x1 {
    guard let colour = bitmap.colorAt(x: x, y: y) else { continue }
    let r: Double = colour.redComponent * 255
    let g: Double = colour.greenComponent * 255
    let b: Double = colour.blueComponent * 255
    let luminance: Double = 0.299 * r + 0.587 * g + 0.114 * b
    print("x=\(x) rgb=\(Int(r)),\(Int(g)),\(Int(b)) lum=\(Int(luminance))")
}
