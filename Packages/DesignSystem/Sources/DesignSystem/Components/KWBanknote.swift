import SwiftUI

/// Cash drawn as a banknote rather than a card: no chip or digits, a framed note with a medallion
/// showing its currency, so it is never mistaken for something you swipe.
public struct KWBanknote: View {
    private let title: String
    private let amount: String
    private let footnote: String?
    private let currency: String

    /// - Parameter footnote: A second line under the amount, such as its value in another currency.
    public init(title: String, amount: String, footnote: String? = nil, currency: String) {
        self.title = title
        self.amount = amount
        self.footnote = footnote
        self.currency = currency
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: KWRadius.input, style: .continuous)
        ZStack {
            KWColor.CardArt.verde.largeGradient
            medallion
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, KWSpacing.xl)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: KWSpacing.xs) {
                    KWIconView(.wallet, size: 18)
                    Text(title)
                        .font(.kw(17, weight: 800))
                        .tracking(-0.3)
                }
                Spacer(minLength: KWSpacing.sm)
                Text(amount)
                    .font(.kw(28, weight: 800))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                if let footnote {
                    Text(footnote)
                        .font(KWTextStyle.captionSm.font)
                        .monospacedDigit()
                        .opacity(0.8)
                }
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(KWSpacing.lg)
        }
        .foregroundStyle(KWColor.Text.primary)
        .aspectRatio(2.2, contentMode: .fit)
        .clipShape(shape)
        // The inner frame is what makes it read as a note.
        .overlay(shape.inset(by: KWSpacing.xs).strokeBorder(.white.opacity(0.28), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    private var medallion: some View {
        ZStack {
            Circle().strokeBorder(.white.opacity(0.22), lineWidth: 10)
            Circle().strokeBorder(.white.opacity(0.18), lineWidth: 1).padding(16)
            Text(verbatim: currency)
                .font(.kw(15, weight: 800))
                .opacity(0.85)
        }
        .frame(width: 84, height: 84)
        .accessibilityHidden(true)
    }
}

#Preview {
    KWBanknote(title: "Cash", amount: "C$30,000", footnote: "≈ $817.79", currency: "NIO")
        .padding(KWLayout.gutter)
        .background(KWColor.Surface.bg)
        .onAppear { KWFonts.register() }
}
