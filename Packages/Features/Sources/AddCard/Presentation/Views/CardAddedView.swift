import DesignSystem
import SharedPresentation
import SwiftUI

/// Step 4 · Added.
public struct CardAddedView: View {
    private let viewModel: AddCardViewModel
    private let onViewCard: () -> Void
    private let onAddAnother: () -> Void

    public init(viewModel: AddCardViewModel, onViewCard: @escaping () -> Void, onAddAnother: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onViewCard = onViewCard
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
                    holder: viewModel.printedName,
                    lastFour: viewModel.lastFour,
                    numberGroups: CardDisplay.numberGroups(for: viewModel.network),
                    network: CardDisplay.networkMark(for: viewModel.network),
                    kindLabel: viewModel.kind == .credit
                        ? String(localized: "Credit", bundle: #bundle)
                        : String(localized: "Debit", bundle: #bundle),
                )
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
}
