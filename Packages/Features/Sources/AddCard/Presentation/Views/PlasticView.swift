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
        case lastFour
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
        .kwKeyboardToolbar($focus, order: [.bank, .lastFour])
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: KWSpacing.md) {
            KWFlowHeader(.back, progress: viewModel.kind == .credit ? (2, 1) : (1, 1), action: onBack)
            Text(viewModel.plasticTitle).kwTextStyle(.titleSm).accessibilityAddTraits(.isHeader)
            KWCardArt(
                palette: CardDisplay.palette(for: viewModel.color),
                bank: viewModel.bank.isEmpty ? bankPlaceholder : viewModel.bank,
                badge: .tag(kindBadge),
                showsContactless: false,
                lastFour: viewModel.lastFour.isEmpty ? "0000" : viewModel.lastFour,
                network: CardDisplay.wordmark(for: viewModel.network),
            )
            swatches
            KWGroupedCard {
                if viewModel.kind == .debit {
                    accountPicker
                }
                KWTextFieldRow(
                    String(localized: "Bank", bundle: #bundle),
                    placeholder: String(localized: "Bank name", bundle: #bundle),
                    text: $viewModel.bank,
                )
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .kwFocused($focus, equals: .bank)
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
            Text("We never ask for the full number or the CVV.", bundle: #bundle)
                .font(KWTextStyle.captionSm.font)
                .foregroundStyle(KWColor.Text.muted)
            if let error = viewModel.errorMessage {
                Text(error).font(KWTextStyle.caption.font).foregroundStyle(KWColor.State.negative)
            }
        }
    }

    private var bankPlaceholder: String {
        let fallback = String(localized: "Bank", bundle: #bundle)
        return viewModel.kind == .debit
            ? viewModel.context?.depositAccounts.first { $0.id == viewModel.linkedAccountID }?.bank ?? fallback
            : fallback
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

    private var accountPicker: some View {
        VStack(alignment: .leading, spacing: KWSpacing.xs) {
            Text("Account", bundle: #bundle).foregroundStyle(KWColor.Text.secondary).font(KWTextStyle.body.font)
            KWFlowLayout(spacing: 6) {
                ForEach(viewModel.context?.depositAccounts ?? []) { account in
                    KWChip(CardDisplay.name(of: account), isSelected: account.id == viewModel.linkedAccountID) {
                        viewModel.linkedAccountID = account.id
                    }
                }
            }
        }
        .padding(.vertical, KWSpacing.sm)
    }
}
