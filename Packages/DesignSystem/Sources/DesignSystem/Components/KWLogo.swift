import SwiftUI

/// The keepwell figure (head and cupped arc), drawn from the brand's 72×72 artwork.
public struct KWLogoMark: View {
    private let size: CGFloat

    public init(size: CGFloat) {
        self.size = size
    }

    public var body: some View {
        let scale = size / 72
        ZStack {
            Circle()
                .frame(width: 18 * scale, height: 18 * scale)
                .position(x: 36 * scale, y: 21 * scale)
            LogoArc()
                .stroke(style: StrokeStyle(lineWidth: 7.5 * scale, lineCap: .round))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

private struct LogoArc: Shape {
    func path(in rect: CGRect) -> Path {
        SVGPath.path(from: "M15 34v7a21 21 0 0 0 42 0v-7")
            .applying(CGAffineTransform(scaleX: rect.width / 72, y: rect.height / 72))
    }
}

/// Logo mark on the brand gradient tile, as on the lock screen (72pt, radius 17).
public struct KWAppIconTile: View {
    public init() {}

    public var body: some View {
        KWLogoMark(size: 44)
            .foregroundStyle(.white)
            .frame(width: 72, height: 72)
            .background(
                LinearGradient(colors: [KWColor.Brand.b500, KWColor.Brand.b700], startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 17, style: .continuous),
            )
            .overlay { TopHighlight(shape: RoundedRectangle(cornerRadius: 17, style: .continuous), opacity: 0.3) }
    }
}

/// Mark followed by the "keepwell" wordmark.
public struct KWWordmark: View {
    private let markSize: CGFloat
    private let fontSize: CGFloat

    public init(markSize: CGFloat = 50, fontSize: CGFloat = 46) {
        self.markSize = markSize
        self.fontSize = fontSize
    }

    public var body: some View {
        HStack(spacing: 10) {
            KWLogoMark(size: markSize)
            Text("keepwell")
                .font(.kw(fontSize, weight: 800, relativeTo: .largeTitle))
                .tracking(-2)
        }
        .foregroundStyle(.white)
        .accessibilityElement()
        .accessibilityLabel("keepwell")
    }
}

#Preview {
    VStack(spacing: KWSpacing.xl) {
        KWAppIconTile()
        KWWordmark()
    }
    .padding(KWLayout.gutter)
    .background(KWColor.Brand.b700)
    .onAppear { KWFonts.register() }
}
