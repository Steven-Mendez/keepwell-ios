import Core
import DesignSystem
import Domain
import SharedPresentation
import SwiftUI

/// Step 2 · Plastic: art preview, color, bank, last digits and network.
public struct PlasticView: View {
    @Bindable private var viewModel: AddCardViewModel
    private let onBack: () -> Void
    @FocusState private var focus: Field?

    private enum Field: Hashable {
        case bank
        case accountName
        case lastFour
        case balance
    }

    public init(viewModel: AddCardViewModel, onBack: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onBack = onBack
    }

    private var kindBadge: String {
        viewModel.kind == .credit ? String(localized: "Credit", bundle: #bundle) : String(localized: "Debit", bundle: #bundle)
    }

    public var body: some View {
        KWFormScreen {
            form
        } footer: {
            Button {
                focus = nil
                Task { await viewModel.continueFromPlastic() }
            } label: {
                Text(viewModel.kind == .credit ? "Continue" : "Add card", bundle: #bundle)
            }
            .buttonStyle(.kw())
            .disabled(!viewModel.canContinueFromPlastic || viewModel.isSaving)
        }
        .kwKeyboardToolbar($focus, order: viewModel.kind == .debit ? [.bank, .accountName, .lastFour, .balance] : [.bank, .lastFour])
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: KWSpacing.md) {
            KWFlowHeader(.back, progress: viewModel.kind == .credit ? (2, 1) : (1, 1), action: onBack)
            Text(viewModel.plasticTitle).kwTextStyle(.titleSm).accessibilityAddTraits(.isHeader)
            KWCardArt(
                palette: CardDisplay.palette(for: viewModel.color),
                bank: viewModel.bank.isEmpty ? bankPlaceholder : viewModel.bank,
                showsContactless: false,
                lastFour: viewModel.lastFour.isEmpty ? "0000" : viewModel.lastFour,
                numberGroups: CardDisplay.numberGroups(for: viewModel.network),
                network: CardDisplay.networkMark(for: viewModel.network),
                kindLabel: kindBadge,
            )
            swatches
            plasticFields
            if viewModel.kind == .debit {
                balanceFields
            }
            Text("We never ask for the full number or the CVV.", bundle: #bundle)
                .font(KWTextStyle.captionSm.font)
                .foregroundStyle(KWColor.Text.muted)
            if let error = viewModel.errorMessage {
                Text(error).font(KWTextStyle.caption.font).foregroundStyle(KWColor.State.negative)
            }
        }
    }

    private var plasticFields: some View {
        KWGroupedCard {
            KWTextFieldRow(
                String(localized: "Bank", bundle: #bundle),
                placeholder: String(localized: "Bank name", bundle: #bundle),
                text: $viewModel.bank,
            )
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled()
            .kwFocused($focus, equals: .bank)
            if viewModel.kind == .debit {
                KWTextFieldRow(
                    String(localized: "Account", bundle: #bundle),
                    placeholder: String(localized: "Savings", bundle: #bundle),
                    text: $viewModel.accountName,
                )
                .textInputAutocapitalization(.words)
                .kwFocused($focus, equals: .accountName)
            }
            KWTextFieldRow(
                String(localized: "Last 4 digits", bundle: #bundle),
                placeholder: "0000",
                text: $viewModel.lastFour,
                digitLimit: 4,
                width: 110,
            )
            .kwFocused($focus, equals: .lastFour)
            networkPicker
        }
    }

    private var bankPlaceholder: String {
        String(localized: "Bank", bundle: #bundle)
    }

    private var swatches: some View {
        HStack(spacing: KWSpacing.sm) {
            ForEach(KWColor.CardArt.selectable, id: \.self) { palette in
                let isSelected = CardDisplay.cardColor(for: palette) == viewModel.color
                Button { viewModel.color = CardDisplay.cardColor(for: palette) } label: {
                    Circle()
                        .fill(palette.gradient)
                        .frame(width: 36, height: 36)
                        .padding(isSelected ? 3 : 0)
                        .background(isSelected ? Color.black : .clear, in: Circle())
                        .padding(isSelected ? 2 : 0)
                        .background(isSelected ? Color.white : .clear, in: Circle())
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(palette.displayName)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var networkPicker: some View {
        VStack(alignment: .leading, spacing: KWSpacing.xs) {
            Text("Network", bundle: #bundle).foregroundStyle(KWColor.Text.secondary).font(KWTextStyle.body.font)
            HStack(spacing: 6) {
                ForEach(CardNetwork.allCases, id: \.self) { network in
                    let isSelected = network == viewModel.network
                    Button { viewModel.network = network } label: {
                        Text(CardDisplay.networkName(network))
                            .font(.kw(13, weight: 600, relativeTo: .footnote))
                            .foregroundStyle(isSelected ? Color.black : KWColor.Text.secondary)
                            .padding(.horizontal, KWSpacing.sm)
                            .frame(height: 34)
                            .background(isSelected ? Color.white : KWColor.Surface.surface2, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
        .padding(.vertical, KWSpacing.sm)
    }

    /// The debit card is the bank account, so its balance is asked here rather than in a second form.
    private var balanceFields: some View {
        KWGroupedCard {
            if let second = viewModel.second {
                HStack {
                    Text("Currency", bundle: #bundle).foregroundStyle(KWColor.Text.secondary)
                    Spacer()
                    KWSegmentedControl(
                        [(value: viewModel.principal, title: viewModel.principal), (value: second, title: second)],
                        selection: Binding(get: { viewModel.accountCurrencyCode }, set: { viewModel.accountCurrency = $0 }),
                        style: .accent,
                    )
                }
                .font(KWTextStyle.body.font)
                .padding(.vertical, 10)
            }
            KWAmountFieldRow(
                String(localized: "Today's balance", bundle: #bundle),
                symbol: CurrencyFormatter.symbol(for: viewModel.accountCurrencyCode),
                text: $viewModel.balanceText,
            )
            .kwFocused($focus, equals: .balance)
        }
    }
}
