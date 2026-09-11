import SwiftUI

/// Shared 4-point spacing scale. Components use the smallest value that makes
/// their semantic relationship clear instead of accumulating near-duplicates.
enum LayoutSpacing {
    static let micro: CGFloat = 4
    static let tight: CGFloat = 8
    static let compact: CGFloat = 12
    static let standard: CGFloat = 16
    static let section: CGFloat = 20
    static let page: CGFloat = 24
    static let region: CGFloat = 32
}

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
        // Provider names always sit beside the mark. Keeping the decorative
        // image out of the accessibility tree avoids announcing it twice.
        .accessibilityHidden(true)
    }
}

/// Bar tint. Provider colors identify the service; semantic colors take over
/// only when the remaining allowance itself needs attention.
func usageTint(for window: UsageWindow?, accent: Color) -> Color {
    guard let remaining = window?.remainingPercent else { return .secondary }
    if remaining <= 10 { return .red }
    if remaining <= 20 { return .orange }
    return accent
}

/// Figure tint.
///
/// Claude's brand accent *is* orange, so tinting a healthy Claude percentage
/// with it makes 97% look exactly as alarming as the amber warning beside it.
/// The number therefore stays neutral until the allowance genuinely needs
/// attention, and a coloured figure always means the same thing on both
/// providers. Brand identity still rides on the logo and the bar.
func usageValueTint(for window: UsageWindow?) -> Color {
    guard let remaining = window?.remainingPercent else { return .secondary }
    if remaining <= 10 { return .red }
    if remaining <= 20 { return .orange }
    return .primary
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
            }
        }
        // Every use has an adjacent textual percentage. The bar is a redundant
        // visual encoding, not an additional VoiceOver stop.
        .accessibilityHidden(true)
    }
}
