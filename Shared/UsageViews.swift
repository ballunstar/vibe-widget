import SwiftUI

extension ProviderUsage.Provider {
    /// Official provider brand colours used throughout the app and widget.
    var accent: Color {
        switch self {
        case .claude:
            return Color(red: 217.0 / 255.0, green: 119.0 / 255.0, blue: 87.0 / 255.0)
        case .codex:
            return Color(red: 16.0 / 255.0, green: 163.0 / 255.0, blue: 127.0 / 255.0)
        }
    }
}

extension View {
    /// Forces light or dark, or leaves the view following the system.
    ///
    /// The widget runs in its own process and never sees `NSApp.appearance`,
    /// so it has to be told through the environment instead.
    @ViewBuilder
    func applyAppearance(_ appearance: AppSettings.Appearance) -> some View {
        if let scheme = appearance.colorScheme {
            self.environment(\.colorScheme, scheme)
        } else {
            self
        }
    }
}

/// A provider's logo at a given edge length.
///
/// Loaded through `NSImage(named:)` rather than `Image("name")`: the SwiftUI
/// initialiser resolves against an asset catalog, and these ship as loose PNGs
/// in each target's Resources. `NSImage` searches those by filename.
struct ProviderLogo: View {
    let provider: ProviderUsage.Provider
    let size: CGFloat

    var body: some View {
        Group {
            if let image = NSImage(named: provider.logoAsset) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                // Bundled with both targets, so this should not happen — but a
                // tinted dot beats an invisible gap if a build ever misses it.
                Circle().fill(provider.accent)
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Gauges
//
// Shared with the widget target, so both draw the same shapes.

/// The dashed ring around each percentage. Ticks rather than a solid arc so a
/// glance reads roughly how full it is without reading the number.
struct RingGauge: View {
    let remaining: Double
    let tint: Color
    var diameter: CGFloat = 74

    private let tickCount = 36

    var body: some View {
        ZStack {
            ForEach(0..<tickCount, id: \.self) { index in
                let threshold = Double(index) / Double(tickCount) * 100
                Capsule()
                    .fill(threshold < remaining ? tint : Color.primary.opacity(0.12))
                    .frame(width: 2.5, height: 8)
                    .offset(y: -diameter / 2 + 4)
                    .rotationEffect(.degrees(Double(index) / Double(tickCount) * 360))
            }
            Text("\(Int(remaining.rounded()))%")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
        .frame(width: diameter, height: diameter)
    }
}

/// Chunked progress bar. Discrete blocks make small differences visible in a
/// way a continuous fill does not.
struct SegmentedBar: View {
    let remaining: Double
    let tint: Color
    var segments: Int = 8

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<segments, id: \.self) { index in
                let start = Double(index) / Double(segments) * 100
                let end = Double(index + 1) / Double(segments) * 100
                // The segment straddling the value is partially filled, so the
                // bar does not jump a whole block at a time.
                let fill = min(1, max(0, (remaining - start) / (end - start)))
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.08))
                        if fill > 0 {
                            Capsule().fill(tint).frame(width: geo.size.width * fill)
                        }
                    }
                }
                .frame(height: 9)
            }
        }
    }
}
