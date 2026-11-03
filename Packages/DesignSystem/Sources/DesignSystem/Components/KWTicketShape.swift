import SwiftUI

/// A receipt: rounded top corners and a scalloped bottom edge, as if torn off a printer roll.
public struct KWTicketShape: Shape {
    private let cornerRadius: CGFloat
    private let scallop: CGFloat

    /// `scallop` is the radius of each bite along the bottom edge.
    public init(cornerRadius: CGFloat = KWRadius.surface, scallop: CGFloat = 7) {
        self.cornerRadius = cornerRadius
        self.scallop = scallop
    }

    public func path(in rect: CGRect) -> Path {
        var path = Path()
        let bottom = rect.maxY
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + cornerRadius))
        path.addArc(
            center: CGPoint(x: rect.minX + cornerRadius, y: rect.minY + cornerRadius),
            radius: cornerRadius, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false,
        )
        path.addLine(to: CGPoint(x: rect.maxX - cornerRadius, y: rect.minY))
        path.addArc(
            center: CGPoint(x: rect.maxX - cornerRadius, y: rect.minY + cornerRadius),
            radius: cornerRadius, startAngle: .degrees(270), endAngle: .degrees(0), clockwise: false,
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: bottom))
        // Whole bites only, spread evenly, so both ends meet the sides cleanly.
        let count = max(Int((rect.width / (scallop * 3)).rounded()), 1)
        let step = rect.width / CGFloat(count)
        for index in (0 ..< count).reversed() {
            let center = CGPoint(x: rect.minX + step * (CGFloat(index) + 0.5), y: bottom)
            path.addLine(to: CGPoint(x: center.x + step / 2, y: bottom))
            path.addLine(to: CGPoint(x: center.x + scallop, y: bottom))
            path.addArc(center: center, radius: scallop, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: true)
            path.addLine(to: CGPoint(x: center.x - step / 2, y: bottom))
        }
        path.closeSubpath()
        return path
    }
}

#Preview {
    KWTicketShape()
        .fill(KWColor.Surface.surface)
        .frame(height: 300)
        .padding(KWLayout.gutter)
        .background(KWColor.Surface.bg)
}
