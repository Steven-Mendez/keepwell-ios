import SwiftUI

/// The payment networks a card face can print. Drawn here rather than taken from the domain
/// because each one has its own mark.
public enum KWCardNetwork: Sendable, Equatable {
    case visa
    case mastercard
    case amex
}

/// Card artwork at the 1.586:1 credit-card ratio, laid out like a real plastic: bank and badge on
/// top, chip and contactless, then the holder, the masked number and the network with the card's
/// kind under it. Every part is optional because screens show different subsets: a card at the
/// back of a stack only shows its header, the add-card preview has no contactless mark.
///
/// The face is drawn on a fixed 358pt canvas and scaled to the width it gets, so a small preview
/// and the hero card on a detail screen keep the same proportions.
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
    private let holder: String?
    private let caption: String?
    private let lastFour: String?
    private let numberGroups: [Int]
    private let network: KWCardNetwork?
    private let kindLabel: String?
    private let isFrozen: Bool
    private let showsShadow: Bool

    static let designWidth: CGFloat = 358
    static let designHeight: CGFloat = designWidth / KWComponentMetrics.cardArtRatio

    /// - Parameters:
    ///   - holder: The name printed on the plastic, when the card has one.
    ///   - numberGroups: How the network groups the full number (4-4-4-4, or 4-6-5 for Amex), so
    ///     the masked digits read like the real card.
    ///   - kindLabel: "Debit" or "Credit", printed under the network mark.
    public init(
        palette: KWColor.CardArt,
        bank: String,
        badge: Badge? = nil,
        showsChip: Bool = true,
        showsContactless: Bool = true,
        holder: String? = nil,
        caption: String? = nil,
        lastFour: String? = nil,
        numberGroups: [Int] = [4, 4, 4, 4],
        network: KWCardNetwork? = nil,
        kindLabel: String? = nil,
        isFrozen: Bool = false,
        showsShadow: Bool = true,
    ) {
        self.palette = palette
        self.bank = bank
        self.badge = badge
        self.showsChip = showsChip
        self.showsContactless = showsContactless
        self.holder = holder
        self.caption = caption
        self.lastFour = lastFour
        self.numberGroups = numberGroups
        self.network = network
        self.kindLabel = kindLabel
        self.isFrozen = isFrozen
        self.showsShadow = showsShadow
    }

    /// "•••• •••• •••• 6019": every digit but the last four masked, spaced as the network prints them.
    public static func maskedNumber(lastFour: String, groups: [Int] = [4, 4, 4, 4]) -> String {
        let total = max(groups.reduce(0, +), lastFour.count)
        var characters = Array(repeating: Character("•"), count: total - lastFour.count) + Array(lastFour)
        var parts: [String] = []
        for size in groups where !characters.isEmpty {
            parts.append(String(characters.prefix(size)))
            characters.removeFirst(min(size, characters.count))
        }
        if !characters.isEmpty {
            parts.append(String(characters))
        }
        return parts.joined(separator: " ")
    }

    public var body: some View {
        Color.clear
            .aspectRatio(KWComponentMetrics.cardArtRatio, contentMode: .fit)
            .overlay {
                GeometryReader { proxy in
                    face
                        .scaleEffect(proxy.size.width / Self.designWidth, anchor: .topLeading)
                }
            }
            .kwShadow(showsShadow && !isFrozen ? palette.glow : KWShadow(color: .clear, radius: 0, x: 0, y: 0))
            .accessibilityElement(children: .combine)
    }

    private var face: some View {
        let shape = RoundedRectangle(cornerRadius: KWRadius.card, style: .continuous)
        // Decoration sits in the background so its oversized circles never size the face.
        return content
            .padding(.horizontal, 22)
            .padding(.vertical, 20)
            .frame(width: Self.designWidth, height: Self.designHeight)
            .background {
                ZStack {
                    background
                    CardOrbs(opacity: isFrozen ? 0.05 : palette.orbOpacity)
                    if isFrozen {
                        KWIconView(.freeze, size: 100, lineWidth: 1.2)
                            .foregroundStyle(.white.opacity(0.07))
                            .offset(x: 100, y: -16)
                            .accessibilityHidden(true)
                    }
                }
            }
            .foregroundStyle(foreground)
            .clipShape(shape)
            .overlay { TopHighlight(shape: shape, opacity: palette.isLight ? 0.5 : 0.3) }
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
            if showsChip {
                HStack(spacing: KWSpacing.sm) {
                    KWCardChip(width: 44, height: 33, cornerRadius: 7)
                    if showsContactless {
                        KWIconView(.contactless, size: 22)
                            .foregroundStyle(palette.isLight || isFrozen ? AnyShapeStyle(foreground) : AnyShapeStyle(.white.opacity(0.85)))
                    }
                }
                .padding(.top, 18)
            }
            Spacer(minLength: 0)
            footer
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(bank)
                .font(.kw(18, weight: 800))
                .tracking(-0.3)
            Spacer(minLength: KWSpacing.xs)
            switch badge {
            case let .tag(text):
                HStack(spacing: 4) {
                    if isFrozen {
                        KWIconView(.freeze, size: 12, lineWidth: 2.2)
                    }
                    Text(text)
                }
                .font(.kw(12, weight: 700))
                .padding(.vertical, KWSpacing.xxs)
                .padding(.horizontal, KWSpacing.xs)
                .background(
                    palette.isLight && !isFrozen ? KWColor.Overlay.black12 : KWColor.Overlay.white18,
                    in: RoundedRectangle(cornerRadius: 8),
                )
            case let .amount(text):
                Text(text)
                    .font(.kw(15, weight: 700))
                    .monospacedDigit()
                    .minimumScaleFactor(0.7)
            case nil:
                EmptyView()
            }
        }
        .lineLimit(1)
    }

    @ViewBuilder
    private var footer: some View {
        if holder != nil || caption != nil || lastFour != nil || network != nil || kindLabel != nil {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 5) {
                    if let holder {
                        Text(holder)
                            .font(.kw(14, weight: 600))
                            .opacity(0.92)
                    }
                    if let lastFour {
                        Text(Self.maskedNumber(lastFour: lastFour, groups: numberGroups))
                            .font(.kw(17, weight: 600))
                            .monospacedDigit()
                            .tracking(1.2)
                    }
                    if let caption {
                        Text(caption)
                            .font(.kw(12, weight: 500))
                            .opacity(0.8)
                    }
                }
                .minimumScaleFactor(0.7)
                Spacer(minLength: KWSpacing.xs)
                if network != nil || kindLabel != nil {
                    VStack(alignment: .trailing, spacing: 3) {
                        if let network {
                            KWNetworkMark(network, isMuted: isFrozen)
                        }
                        if let kindLabel {
                            Text(kindLabel)
                                .font(.kw(11, weight: 600))
                                .opacity(0.85)
                        }
                    }
                }
            }
            .lineLimit(1)
        }
    }
}

/// The network's mark as printed on a plastic: the Visa and Amex wordmarks, Mastercard's circles.
public struct KWNetworkMark: View {
    private let network: KWCardNetwork
    private let isMuted: Bool

    public init(_ network: KWCardNetwork, isMuted: Bool = false) {
        self.network = network
        self.isMuted = isMuted
    }

    public var body: some View {
        switch network {
        case .visa:
            wordmark("VISA")
        case .amex:
            wordmark("AMEX")
        case .mastercard:
            // A frozen card keeps the shape of the mark but loses its color, like the rest of the face.
            HStack(spacing: -12) {
                Circle().fill(Color(hex: 0xEB001B))
                Circle().fill(Color(hex: 0xF79E1B).opacity(0.9))
            }
            .frame(width: 50, height: 30)
            .saturation(isMuted ? 0 : 1)
            .opacity(isMuted ? 0.5 : 1)
            .accessibilityElement()
            .accessibilityLabel(Text(verbatim: "Mastercard"))
        }
    }

    /// Heavy, slanted, tight. Inter ships no italic here, so the slant is a skew.
    private func wordmark(_ name: String) -> some View {
        Text(verbatim: name)
            .font(.kw(22, weight: 800))
            .tracking(-0.5)
            .transformEffect(CGAffineTransform(a: 1, b: 0, c: -0.2, d: 1, tx: 4, ty: 0))
    }
}

/// The gold EMV chip, with its contact pads.
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
            .overlay { pads.stroke(.black.opacity(0.18), lineWidth: 1) }
            .overlay(RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(.black.opacity(0.15), lineWidth: 1))
            .frame(width: width, height: height)
            .accessibilityHidden(true)
    }

    private var pads: Path {
        Path { path in
            for y in [height * 0.36, height * 0.64] {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: width * 0.34, y: y))
                path.move(to: CGPoint(x: width, y: y))
                path.addLine(to: CGPoint(x: width * 0.66, y: y))
            }
            path.addRoundedRect(
                in: CGRect(x: width * 0.34, y: height * 0.22, width: width * 0.32, height: height * 0.56),
                cornerSize: CGSize(width: 3, height: 3),
            )
        }
    }
}

/// Large soft circles bleeding off the left edge and a sheen from the top corner: the light a
/// glossy plastic catches. Sized for the 358pt canvas.
private struct CardOrbs: View {
    let opacity: Double

    var body: some View {
        ZStack {
            Circle()
                .fill(.white.opacity(opacity))
                .frame(width: 330, height: 330)
                .offset(x: -170, y: -10)
            Circle()
                .strokeBorder(.white.opacity(opacity * 0.9), lineWidth: 1)
                .frame(width: 430, height: 430)
                .offset(x: -190, y: 0)
            LinearGradient(
                stops: [.init(color: .white.opacity(opacity * 1.6), location: 0), .init(color: .clear, location: 0.45)],
                startPoint: .topTrailing,
                endPoint: .bottomLeading,
            )
        }
        .allowsHitTesting(false)
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
        KWCardArt(
            palette: .verde,
            bank: "Bank One",
            holder: "Alex Doe",
            caption: "Savings",
            lastFour: "6019",
            network: .visa,
            kindLabel: "Debit",
        )
        KWCardArt(
            palette: .azul,
            bank: "Bank One",
            badge: .tag("Frozen"),
            caption: "Credit · 2 cards",
            lastFour: "1234",
            network: .mastercard,
            kindLabel: "Credit",
            isFrozen: true,
        )
    }
    .padding(KWLayout.gutter)
    .background(KWColor.Surface.bg)
    .onAppear { KWFonts.register() }
}
