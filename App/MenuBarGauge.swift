import AppKit

/// Draws the menu bar mark: a split donut where each half is a gauge for one
/// provider, filled in that provider's brand colour.
///
/// Deliberately **not** a template image. A template tells macOS to keep the
/// shape and throw the colour away — which is what makes one asset work on both
/// light and dark menu bars, and exactly what has to be given up to show brand
/// colour. The palette is chosen to read on either bar instead.
enum MenuBarGauge {

    /// Menu bar art sits in a 22pt bar; 18pt is the usual icon box.
    static let side: CGFloat = 18

    /// Clearance in degrees either side of vertical, splitting the two halves.
    private static let verticalGap: CGFloat = 10

    private static let track = NSColor(white: 0.5, alpha: 0.32)

    /// - Parameters:
    ///   - claude: percent remaining, or nil when there is no reading yet.
    ///   - chatgpt: percent remaining, or nil when there is no reading yet.
    static func image(claude: Double?, chatgpt: Double?, side: CGFloat = Self.side) -> NSImage {
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }

            let center = CGPoint(x: rect.midX, y: rect.midY)
            let radius = rect.width * 0.34
            let lineWidth = rect.width * 0.21

            func arc(from startDeg: CGFloat, to endDeg: CGFloat, _ color: NSColor) {
                guard abs(endDeg - startDeg) > 0.5 else { return }
                ctx.saveGState()
                ctx.setStrokeColor(color.cgColor)
                ctx.setLineWidth(lineWidth)
                ctx.setLineCap(.butt)
                ctx.addArc(center: center, radius: radius,
                           startAngle: startDeg * .pi / 180,
                           endAngle: endDeg * .pi / 180,
                           clockwise: startDeg > endDeg)
                ctx.strokePath()
                ctx.restoreGState()
            }

            let sweep = 180 - verticalGap * 2

            // Left half — Claude. Fills upward from 6 o'clock so a full ring
            // reads as "plenty left" rather than as a countdown.
            let claudeStart = 90 + verticalGap
            arc(from: claudeStart, to: claudeStart + sweep, track)
            if let claude {
                let filled = sweep * CGFloat(max(0, min(100, claude))) / 100
                arc(from: claudeStart + sweep - filled, to: claudeStart + sweep,
                    NSColor(srgbRed: 217/255, green: 119/255, blue: 87/255, alpha: 1))
            }

            // Right half — ChatGPT.
            let gptStart = 90 - verticalGap
            arc(from: gptStart, to: gptStart - sweep, track)
            if let chatgpt {
                let filled = sweep * CGFloat(max(0, min(100, chatgpt))) / 100
                arc(from: gptStart - sweep + filled, to: gptStart - sweep,
                    NSColor(srgbRed: 16/255, green: 163/255, blue: 127/255, alpha: 1))
            }
            return true
        }
        // Colour would be discarded if this were a template.
        image.isTemplate = false
        return image
    }
}
