import DesignSystem
import Domain
import SharedPresentation
import SwiftUI

/// Step 2 · Plástico: art preview, color, bank, last digits and network.
public struct PlasticView: View {
    @Bindable private var viewModel: AddCardViewModel
    private let onBack: () -> Void

    public init(viewModel: AddCardViewModel, onBack: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onBack = onBack
    }

    public var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                form
                    .padding(.horizontal, KWLayout.gutter)
                    .padding(.top, KWLayout.safeTop)
                    .padding(.bottom, KWSpacing.md)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            Button(viewModel.kind == .credit ? "Continuar" : "Agregar tarjeta") {
                KWKeyboard.dismiss()
                Task { await viewModel.continueFromPlastic() }
            }
            .buttonStyle(.kw())
            .disabled(!viewModel.canContinueFromPlastic || viewModel.isSaving)
            .padding(.horizontal, KWLayout.gutter)
            .padding(.top, KWSpacing.sm)
            .padding(.bottom, 34)
        }
        .ignoresSafeArea(.container, edges: [.top, .bottom])
        .background(KWColor.Surface.bg)
        .foregroundStyle(KWColor.Text.primary)
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: KWSpacing.md) {
            KWFlowHeader(.back, progress: viewModel.kind == .credit ? (2, 1) : (1, 1), action: onBack)
            Text(viewModel.plasticTitle).kwTextStyle(.titleSm).accessibilityAddTraits(.isHeader)
            KWCardArt(
                palette: CardDisplay.palette(for: viewModel.color),
                bank: viewModel.bank.isEmpty ? bankPlaceholder : viewModel.bank,
                badge: .tag(viewModel.kind == .credit ? "Crédito" : "Débito"),
                showsContactless: false,
                lastFour: viewModel.lastFour.isEmpty ? "0000" : viewModel.lastFour,
                network: CardDisplay.wordmark(for: viewModel.network),
            )
            swatches
            KWGroupedCard {
                if viewModel.kind == .debit {
                    accountPicker
                }
                FormTextRow(label: "Banco", placeholder: "Nombre del banco", text: $viewModel.bank)
                FormTextRow(label: "Últimos 4 dígitos", placeholder: "0000", text: lastFourBinding, width: 90, numeric: true)
                networkPicker
            }
            Text("Nunca pedimos el número completo ni el CVV.")
                .font(KWTextStyle.captionSm.font)
                .foregroundStyle(KWColor.Text.muted)
            if let error = viewModel.errorMessage {
                Text(error).font(KWTextStyle.caption.font).foregroundStyle(KWColor.State.negative)
            }
        }
    }

    private var bankPlaceholder: String {
        viewModel.kind == .debit
            ? viewModel.context?.depositAccounts.first { $0.id == viewModel.linkedAccountID }?.bank ?? "Banco"
            : "Banco"
    }

    private var lastFourBinding: Binding<String> {
        Binding(get: { viewModel.lastFour }, set: { viewModel.lastFour = String($0.filter(\.isNumber).prefix(4)) })
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
            Text("Red").foregroundStyle(KWColor.Text.secondary).font(KWTextStyle.body.font)
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
            Text("Cuenta").foregroundStyle(KWColor.Text.secondary).font(KWTextStyle.body.font)
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
