import SwiftUI

/// Card artwork at the 1.586:1 credit-card ratio. Every part is optional because screens show
/// different subsets: the stacked back card only has its header, the add-card preview has no
/// contactless mark, the detail card adds a role tag.
public struct KWCardArt: View {
    public enum Badge: Sendable, Equatable {
        /// Pill such as "Holder", "Additional", "Credit" or "Frozen".
        case tag(String)
        /// Balance in the top-right corner, as on the accounts stack.
        case amount(String)
    }

    private let palette: KWColor.CardArt
    private let bank: String
    private let badge: Badge?
    private let showsChip: Bool
    private let showsContactless: Bool
    private let caption: String?
    private let lastFour: String?
    private let network: String?
    private let isFrozen: Bool
    private let showsShadow: Bool

    public init(
        palette: KWColor.CardArt,
        bank: String,
        badge: Badge? = nil,
        showsChip: Bool = true,
        showsContactless: Bool = true,
        caption: String? = nil,
        lastFour: String? = nil,
        network: String? = nil,
        isFrozen: Bool = false,
        showsShadow: Bool = true,
    ) {
        self.palette = palette
        self.bank = bank
        self.badge = badge
        self.showsChip = showsChip
        self.showsContactless = showsContactless
        self.caption = caption
        self.lastFour = lastFour
        self.network = network
        self.isFrozen = isFrozen
        self.showsShadow = showsShadow
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: KWRadius.card, style: .continuous)
        ZStack {
            background
            CardWaves(opacities: isFrozen ? (0.10, 0.07) : palette.waveOpacities)
            content
                .padding(KWSpacing.lg)
        }
        .foregroundStyle(foreground)
        .aspectRatio(KWComponentMetrics.cardArtRatio, contentMode: .fit)
        .clipShape(shape)
        .overlay { TopHighlight(shape: shape, opacity: palette.isLight ? 0.5 : 0.3) }
        .kwShadow(showsShadow && !isFrozen ? palette.glow : KWShadow(color: .clear, radius: 0, x: 0, y: 0))
        .accessibilityElement(children: .combine)
    }

    private var foreground: Color {
        isFrozen ? KWColor.Text.secondary : palette.foreground
    }

    @ViewBuilder
    private var background: some View {
        if isFrozen {
            LinearGradient(
                colors: [KWColor.Surface.controlOff, Color(hex: 0x1E1E24)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing,
            )
        } else {
            palette.largeGradient
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Spacer(minLength: 0)
            if showsChip {
                HStack(spacing: KWSpacing.sm) {
                    KWCardChip(width: 46, height: 34, cornerRadius: 7)
                    if showsContactless {
                        KWIconView(.contactless, size: 22)
                            .foregroundStyle(palette.isLight ? AnyShapeStyle(foreground) : AnyShapeStyle(.white.opacity(0.85)))
                    }
                }
            }
            Spacer(minLength: 0)
            footer
        }
    }

    private var header: some View {
        HStack {
            Text(bank)
                .font(.kw(17, weight: 800))
                .tracking(-0.3)
            Spacer(minLength: KWSpacing.xs)
            switch badge {
            case let .tag(text):
                Text(text)
                    .font(.kw(12, weight: 700, relativeTo: .caption))
                    .padding(.vertical, KWSpacing.xxs)
                    .padding(.horizontal, KWSpacing.xs)
                    .background(
                        palette.isLight && !isFrozen ? KWColor.Overlay.black12 : KWColor.Overlay.white18,
                        in: RoundedRectangle(cornerRadius: 8),
                    )
            case let .amount(text):
                Text(text)
                    .font(.kw(14, weight: 700, relativeTo: .subheadline))
                    .monospacedDigit()
            case nil:
                EmptyView()
            }
        }
        .lineLimit(1)
    }

    @ViewBuilder
    private var footer: some View {
        if caption != nil || lastFour != nil || network != nil {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: KWSpacing.xxs) {
                    if let caption {
                        Text(caption)
                            .font(KWTextStyle.captionSm.font)
                            .opacity(0.8)
                    }
                    if let lastFour {
                        Text("•••• \(lastFour)")
                            .font(.kw(17, weight: 600))
                            .tracking(2)
                    }
                }
                Spacer(minLength: KWSpacing.xs)
                if let network {
                    KWNetworkWordmark(network)
                }
            }
            .lineLimit(1)
        }
    }
}

/// Network name drawn like the card wordmarks: heavy, slanted, tight. Inter ships no italic
/// here, so the slant is a skew.
public struct KWNetworkWordmark: View {
    private let name: String

    public init(_ name: String) {
        self.name = name
    }

    public var body: some View {
        Text(name)
            .font(.kw(20, weight: 800))
            .tracking(-0.5)
            .transformEffect(CGAffineTransform(a: 1, b: 0, c: -0.2, d: 1, tx: 4, ty: 0))
    }
}

/// The gold EMV chip.
public struct KWCardChip: View {
    private let width: CGFloat
    private let height: CGFloat
    private let cornerRadius: CGFloat

    public init(width: CGFloat, height: CGFloat, cornerRadius: CGFloat) {
        self.width = width
        self.height = height
        self.cornerRadius = cornerRadius
    }

    public var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(KWColor.CardArt.chip.gradient)
            .overlay(RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(.black.opacity(0.15), lineWidth: 1))
            .frame(width: width, height: height)
    }
}

/// The two translucent waves the design draws across every large card (358×226 viewBox,
/// stretched to the card).
private struct CardWaves: View {
    let opacities: (front: Double, back: Double)

    var body: some View {
        GeometryReader { proxy in
            let scale = CGAffineTransform(scaleX: proxy.size.width / 358, y: proxy.size.height / 226)
            ZStack {
                SVGPath.path(from: "M-10 170 C 90 110 170 230 370 130")
                    .applying(scale)
                    .stroke(.white.opacity(opacities.front), lineWidth: 46 * proxy.size.height / 226)
                SVGPath.path(from: "M-10 60 C 120 0 220 120 370 40")
                    .applying(scale)
                    .stroke(.white.opacity(opacities.back), lineWidth: 30 * proxy.size.height / 226)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Approximates the CSS `inset 0 1px 0 rgba(255,255,255,α)` top highlight.
struct TopHighlight<S: InsettableShape>: View {
    let shape: S
    let opacity: Double

    var body: some View {
        shape
            .strokeBorder(
                LinearGradient(
                    stops: [.init(color: .white.opacity(opacity), location: 0), .init(color: .clear, location: 0.04)],
                    startPoint: .top,
                    endPoint: .bottom,
                ),
                lineWidth: 1,
            )
            .allowsHitTesting(false)
    }
}

#Preview {
    VStack(spacing: KWSpacing.xl) {
        KWCardArt(palette: .azul, bank: "Bank One", badge: .tag("Holder"), caption: "Credit", lastFour: "1234", network: "mastercard")
        KWCardArt(palette: .lima, bank: "Bank One", badge: .tag("Additional"), caption: "Family", lastFour: "5678", network: "mastercard")
    }
    .padding(KWLayout.gutter)
    .background(KWColor.Surface.bg)
    .onAppear { KWFonts.register() }
}
