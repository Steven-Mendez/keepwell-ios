import DesignSystem
import SharedPresentation
import SwiftUI

/// Step 4 · Added.
public struct CardAddedView: View {
    private let viewModel: AddCardViewModel
    private let onViewCard: () -> Void
    private let onAddAdditional: () -> Void
    private let onAddAnother: () -> Void

    public init(
        viewModel: AddCardViewModel,
        onViewCard: @escaping () -> Void,
        onAddAdditional: @escaping () -> Void,
        onAddAnother: @escaping () -> Void,
    ) {
        self.viewModel = viewModel
        self.onViewCard = onViewCard
        self.onAddAdditional = onAddAdditional
        self.onAddAnother = onAddAnother
    }

    public var body: some View {
        KWScreen(top: 110, bottom: 34) {
            KWGlowBackground(.navy)
        } content: {
            VStack(spacing: 18) {
                KWCardArt(
                    palette: CardDisplay.palette(for: viewModel.color),
                    bank: viewModel.bank.isEmpty ? String(localized: "Bank", bundle: #bundle) : viewModel.bank,
                    showsContactless: false,
                    lastFour: viewModel.lastFour,
                    network: CardDisplay.wordmark(for: viewModel.network),
                )
                .rotationEffect(.degrees(-3))
                VStack(spacing: KWSpacing.xs) {
                    Text("Card added", bundle: #bundle).kwTextStyle(.titleSm).accessibilityAddTraits(.isHeader)
                    Text(viewModel.summary)
                        .font(KWTextStyle.body.font)
                        .foregroundStyle(KWColor.Text.onBrand)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 10)
                if viewModel.kind == .credit {
                    additionalRow
                }
                Spacer(minLength: 0)
                VStack(spacing: 0) {
                    Button(action: onViewCard) { Text("View card", bundle: #bundle) }.buttonStyle(.kw())
                    Button(action: onAddAnother) { Text("Add another", bundle: #bundle) }
                        .buttonStyle(KWButtonStyle(.plain, size: .text, height: 40))
                        .padding(.top, 18)
                }
            }
        }
    }

    private var additionalRow: some View {
        Button(action: onAddAdditional) {
            HStack(spacing: 14) {
                KWMiniCard(.palette(.lima))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Did you give someone an additional card?", bundle: #bundle).font(.kw(15, weight: 700))
                    Text("Add it with its limit and categories", bundle: #bundle)
                        .font(KWTextStyle.caption.font.weight(.regular))
                        .foregroundStyle(KWColor.Text.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                KWIconView(.chevronRight, size: 18).foregroundStyle(KWColor.Text.muted)
            }
            .foregroundStyle(KWColor.Text.primary)
            .padding(KWSpacing.md)
            .background(KWColor.Surface.surface, in: RoundedRectangle(cornerRadius: KWRadius.surface))
        }
        .buttonStyle(.plain)
    }
}
