// Renders the app icon at a given pixel size.
//
//   swiftc -O -o makeicon Tools/MakeIcon.swift && ./makeicon 1024 out.png
//
// The icon is a split donut: the left half is Claude's coral, the right half is
// Codex's cyan, each broken into three segments. Drawn rather than exported so
// every iconset size is rendered at its own resolution instead of downsampled.

import AppKit
import CoreGraphics
import Foundation

let args = CommandLine.arguments
guard args.count == 3, let size = Int(args[1]) else {
    FileHandle.standardError.write("usage: makeicon <size> <out.png>\n".data(using: .utf8)!)
    exit(2)
}
let outputPath = args[2]
let side = CGFloat(size)

let colorSpace = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                          bytesPerRow: 0, space: colorSpace,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    exit(1)
}
ctx.setAllowsAntialiasing(true)
ctx.interpolationQuality = .high

func rgb(_ r: Int, _ g: Int, _ b: Int, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: a)
}

let coral = rgb(255, 107, 74)
let cyan  = rgb(61, 216, 245)

// macOS rounds app icons with a squircle; leaving a margin keeps the artwork
// clear of the mask the system applies.
let inset = side * 0.085
let rect = CGRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2)
let corner = rect.width * 0.235

let plate = CGPath(roundedRect: rect, cornerWidth: corner, cornerHeight: corner, transform: nil)

// Body: a soft vertical gradient so the plate does not read as flat black.
ctx.saveGState()
ctx.addPath(plate)
ctx.clip()
if let gradient = CGGradient(colorsSpace: colorSpace,
                             colors: [rgb(38, 44, 52), rgb(14, 17, 21)] as CFArray,
                             locations: [0, 1]) {
    ctx.drawLinearGradient(gradient,
                           start: CGPoint(x: 0, y: rect.maxY),
                           end: CGPoint(x: 0, y: rect.minY),
                           options: [])
}
ctx.restoreGState()

// Rim highlight.
ctx.saveGState()
ctx.addPath(plate)
ctx.setStrokeColor(rgb(255, 255, 255, 0.10))
ctx.setLineWidth(side * 0.008)
ctx.strokePath()
ctx.restoreGState()

// MARK: - Ring

let center = CGPoint(x: rect.midX, y: rect.midY)
let ringRadius = rect.width * 0.315
let ringWidth = rect.width * 0.115

/// One segment, occupying exactly the angles given.
///
/// Butt caps, not round: a round cap bulges half the stroke width past the
/// endpoint, which at this thickness turns each segment into a pill and eats
/// the gaps. Flat ends keep them reading as pieces of one ring.
func segmentArc(visibleFrom: CGFloat, visibleTo: CGFloat, color: CGColor) {
    ctx.saveGState()
    ctx.setStrokeColor(color)
    ctx.setLineWidth(ringWidth)
    ctx.setLineCap(.butt)
    ctx.addArc(center: center, radius: ringRadius,
               startAngle: visibleFrom * .pi / 180,
               endAngle: visibleTo * .pi / 180,
               clockwise: false)
    ctx.strokePath()
    ctx.restoreGState()
}

// A gap at 12 and 6 o'clock splits the two halves; two more gaps break each
// half into three segments.
let verticalGap: CGFloat = 6   // visible clearance either side of vertical
let innerGap: CGFloat = 5      // visible gap between segments within a half
let span = 180 - verticalGap * 2
let segment = (span - innerGap * 2) / 3

// Right half (cyan): sweeps down from just below 12 to just above 6.
var edge = 90 - verticalGap
for _ in 0..<3 {
    segmentArc(visibleFrom: edge - segment, visibleTo: edge, color: cyan)
    edge -= segment + innerGap
}

// Left half (coral): sweeps up from just above 12 round to just below 6.
edge = 90 + verticalGap
for _ in 0..<3 {
    segmentArc(visibleFrom: edge, visibleTo: edge + segment, color: coral)
    edge += segment + innerGap
}

// MARK: - Write

guard let image = ctx.makeImage() else { exit(1) }
let rep = NSBitmapImageRep(cgImage: image)
rep.size = NSSize(width: side, height: side)
guard let data = rep.representation(using: .png, properties: [:]) else { exit(1) }
try? data.write(to: URL(fileURLWithPath: outputPath))
