import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("usage: GenerateAppIcon.swift output.png\n", stderr)
    exit(2)
}

let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size)
image.lockFocus()

let canvas = NSRect(origin: .zero, size: size)
let roundedCanvas = NSBezierPath(roundedRect: canvas.insetBy(dx: 14, dy: 14), xRadius: 224, yRadius: 224)
NSGraphicsContext.saveGraphicsState()
roundedCanvas.addClip()
NSGradient(colors: [
    NSColor(calibratedRed: 0.035, green: 0.075, blue: 0.17, alpha: 1),
    NSColor(calibratedRed: 0.055, green: 0.13, blue: 0.28, alpha: 1)
])!.draw(in: canvas, angle: 90)

// The bright capsule touches the upper edge to suggest the island dropping from the menu bar.
let island = NSBezierPath()
island.move(to: NSPoint(x: 304, y: 1040))
island.line(to: NSPoint(x: 720, y: 1040))
island.line(to: NSPoint(x: 720, y: 634))
island.curve(to: NSPoint(x: 594, y: 510), controlPoint1: NSPoint(x: 720, y: 566), controlPoint2: NSPoint(x: 666, y: 510))
island.line(to: NSPoint(x: 430, y: 510))
island.curve(to: NSPoint(x: 304, y: 634), controlPoint1: NSPoint(x: 358, y: 510), controlPoint2: NSPoint(x: 304, y: 566))
island.close()
NSGradient(colors: [
    NSColor(calibratedRed: 0.15, green: 0.72, blue: 0.98, alpha: 1),
    NSColor(calibratedRed: 0.20, green: 0.50, blue: 0.92, alpha: 1)
])!.draw(in: island, angle: 90)

// Small dark marks inside the island read as compact clipboard content at small sizes.
NSColor(calibratedRed: 0.04, green: 0.18, blue: 0.37, alpha: 0.78).setFill()
for (y, width) in [(820, 174), (748, 220), (676, 132)] {
    NSBezierPath(roundedRect: NSRect(x: 512 - width / 2, y: y, width: width, height: 20), xRadius: 10, yRadius: 10).fill()
}

let rowColors = [
    NSColor(calibratedRed: 0.24, green: 0.70, blue: 0.98, alpha: 0.92),
    NSColor(calibratedRed: 0.30, green: 0.84, blue: 0.80, alpha: 0.92),
    NSColor(calibratedRed: 0.55, green: 0.68, blue: 0.98, alpha: 0.92)
]
for (index, color) in rowColors.enumerated() {
    let y = CGFloat(364 - index * 116)
    let row = NSBezierPath(roundedRect: NSRect(x: 250, y: y, width: 524, height: 78), xRadius: 30, yRadius: 30)
    NSColor.white.withAlphaComponent(0.075).setFill()
    row.fill()
    NSBezierPath(ovalIn: NSRect(x: 292, y: y + 23, width: 32, height: 32)).fill()
    color.setFill()
    NSBezierPath(ovalIn: NSRect(x: 292, y: y + 23, width: 32, height: 32)).fill()
    NSColor.white.withAlphaComponent(0.78).setFill()
    NSBezierPath(roundedRect: NSRect(x: 356, y: y + 40, width: 294, height: 13), xRadius: 7, yRadius: 7).fill()
    NSColor.white.withAlphaComponent(0.30).setFill()
    NSBezierPath(roundedRect: NSRect(x: 356, y: y + 20, width: 202, height: 10), xRadius: 5, yRadius: 5).fill()
}

NSGraphicsContext.restoreGraphicsState()
image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    fputs("could not render icon\n", stderr)
    exit(1)
}
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]), options: .atomic)
