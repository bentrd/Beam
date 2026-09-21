#!/usr/bin/env swift
import AppKit
import Foundation

// Beam's app icon, drawn in code (DESIGN.md section 7). There is no Xcode on this machine and therefore no
// asset catalog, so every size is rendered here and packed with `iconutil`.
//
// The icon is a miniature of the reader: six grey bars in two paragraphs, the second one lit. It is the only
// picture of what Beam does that fits in a Dock tile — a page with one part of it found. No letterform, no
// gradient, no glow; at 16 and 32 px it drops to three bars with the middle one lit, because six would silt up.

let body = NSColor(srgbRed: 0.980, green: 0.980, blue: 0.969, alpha: 1)      // warm white paper
let bar = NSColor(srgbRed: 0.788, green: 0.788, blue: 0.769, alpha: 1)       // grey text
let hit = NSColor(srgbRed: 1.0, green: 0.839, blue: 0.039, alpha: 0.55)      // the one highlighter yellow

/// Rounded-rect bars, laid out as two paragraphs whose last line is short, exactly like a page of text.
/// `lines` are fractions of the text width; a nil entry ends a paragraph.
let fullLines: [Double?] = [1.00, 0.94, 0.62, nil, 1.00, 0.90, 0.55]
let smallLines: [Double?] = [1.00, 0.88, nil]

func draw(size: CGFloat, simplified: Bool) -> NSBitmapImageRep {
    let scale = size / 1024
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // The squircle. macOS 26 masks app icons itself, so this only has to be the right shape underneath.
    let plate = NSRect(x: 0, y: 0, width: size, height: size)
    let squircle = NSBezierPath(roundedRect: plate, xRadius: 232 * scale, yRadius: 232 * scale)
    body.setFill()
    squircle.fill()
    NSColor.black.withAlphaComponent(0.08).setStroke()      // a hairline so the paper reads as an edge, not a hole
    squircle.lineWidth = max(1, 2 * scale)
    squircle.stroke()

    let lines = simplified ? smallLines : fullLines
    let inset = (simplified ? 240.0 : 208.0) * scale
    let textWidth = size - inset * 2
    let barHeight = (simplified ? 96.0 : 62.0) * scale
    let lineGap = (simplified ? 84.0 : 52.0) * scale
    let paragraphGap = (simplified ? 84.0 : 104.0) * scale

    // Height of the whole block, so it sits on the optical centre rather than the geometric one.
    var blockHeight = 0.0
    for (index, line) in lines.enumerated() {
        if line == nil { blockHeight += paragraphGap } else {
            blockHeight += barHeight
            if index < lines.count - 1, lines[index + 1] != nil { blockHeight += lineGap }
        }
    }
    var y = (size + blockHeight) / 2 - barHeight

    // The lit paragraph: the second one, or the middle bar when simplified.
    let litIndex = lines.firstIndex(where: { $0 == nil }).map { $0 + 1 }
    var paragraphStart = 0
    var litRect: NSRect?

    for (index, line) in lines.enumerated() {
        guard let fraction = line else { paragraphStart = index + 1; y -= paragraphGap; continue }
        let rect = NSRect(x: inset, y: y, width: textWidth * fraction, height: barHeight)
        if simplified ? index == 1 : (litIndex.map { paragraphStart >= $0 } ?? false) {
            litRect = litRect.map { $0.union(rect) } ?? rect
        }
        y -= barHeight + lineGap
    }

    // The highlight goes down first, so the bars sit on it exactly as a tint sits behind a paragraph.
    if let litRect {
        hit.setFill()
        let padded = litRect.insetBy(dx: -34 * scale, dy: -30 * scale)
        NSBezierPath(roundedRect: padded, xRadius: 28 * scale, yRadius: 28 * scale).fill()
    }

    y = (size + blockHeight) / 2 - barHeight
    paragraphStart = 0
    bar.setFill()
    for (index, line) in lines.enumerated() {
        guard let fraction = line else { paragraphStart = index + 1; y -= paragraphGap; continue }
        let rect = NSRect(x: inset, y: y, width: textWidth * fraction, height: barHeight)
        NSBezierPath(roundedRect: rect, xRadius: barHeight / 2, yRadius: barHeight / 2).fill()
        y -= barHeight + lineGap
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let output = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1]
                                                                  : FileManager.default.currentDirectoryPath + "/tooling")
let iconset = output.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

// The sizes `iconutil` expects, and the two that drop to three bars because six would blur together.
let wanted: [(name: String, pixels: CGFloat)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (name, pixels) in wanted {
    let rep = draw(size: pixels, simplified: pixels <= 32)
    guard let data = rep.representation(using: .png, properties: [:]) else { continue }
    try data.write(to: iconset.appendingPathComponent(name + ".png"))
}

// A 1024 px PNG as well: the Dock preview in a review, and anything that cannot read an .icns.
if let data = draw(size: 1024, simplified: false).representation(using: .png, properties: [:]) {
    try data.write(to: output.appendingPathComponent("AppIcon.png"))
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.appendingPathComponent("AppIcon.icns").path]
try iconutil.run()
iconutil.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
print(iconutil.terminationStatus == 0 ? "AppIcon.icns and AppIcon.png written to \(output.path)"
                                      : "iconutil failed (\(iconutil.terminationStatus))")
