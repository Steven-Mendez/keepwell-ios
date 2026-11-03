import SwiftUI

/// Draws a `KWIcon` at any size in the current foreground style. `lineWidth` is in the icon's
/// 24-unit design space, so a 2-unit stroke stays proportional at 18, 20 or 52 points as in the design.
public struct KWIconView: View {
    private let icon: KWIcon
    private let size: CGFloat
    private let lineWidth: CGFloat

    public init(_ icon: KWIcon, size: CGFloat = 20, lineWidth: CGFloat = KWComponentMetrics.iconStroke) {
        self.icon = icon
        self.size = size
        self.lineWidth = lineWidth
    }

    public var body: some View {
        IconShape(path: icon.path)
            .stroke(
                style: StrokeStyle(
                    lineWidth: lineWidth * size / 24,
                    lineCap: .round,
                    lineJoin: icon.roundJoins ? .round : .miter,
                ),
            )
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

private struct IconShape: Shape {
    let path: Path

    func path(in rect: CGRect) -> Path {
        path.applying(CGAffineTransform(scaleX: rect.width / 24, y: rect.height / 24))
    }
}

#Preview {
    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: KWSpacing.md) {
        ForEach(KWIcon.allCases, id: \.self) { icon in
            KWIconView(icon, size: 24)
        }
    }
    .padding(KWLayout.gutter)
    .foregroundStyle(KWColor.Text.primary)
    .background(KWColor.Surface.bg)
}
