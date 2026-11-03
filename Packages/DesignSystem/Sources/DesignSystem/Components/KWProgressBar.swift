import SwiftUI

/// Horizontal fill bar on a `surface2` track (6pt in rows, 8pt in summary cards).
public struct KWProgressBar: View {
    private let fraction: Double
    private let fill: Color
    private let height: CGFloat

    /// `fraction` is clamped to 0…1.
    public init(_ fraction: Double, fill: Color, height: CGFloat = 6) {
        self.fraction = min(max(fraction, 0), 1)
        self.fill = fill
        self.height = height
    }

    public var body: some View {
        GeometryReader { proxy in
            Capsule()
                .fill(KWColor.Surface.surface2)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(fill)
                        .frame(width: proxy.size.width * fraction)
                }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityValue(Text(fraction, format: .percent.precision(.fractionLength(0))))
    }
}

#Preview {
    VStack(spacing: KWSpacing.md) {
        KWProgressBar(0.54, fill: KWColor.State.extra)
        KWProgressBar(0.29, fill: KWColor.Brand.accent, height: 8)
    }
    .padding(KWLayout.gutter)
    .background(KWColor.Surface.bg)
}
