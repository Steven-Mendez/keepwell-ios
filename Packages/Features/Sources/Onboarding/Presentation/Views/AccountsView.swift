import Core
import DesignSystem
import OnboardingDomain
import SwiftUI

/// Step 3 · Cuentas.
public struct AccountsView: View {
    private let viewModel: OnboardingViewModel
    private let onBack: () -> Void
    private let onImportCSV: () -> Void
    @State private var editing: OnboardingAccountDraft?
    private let formatter = CurrencyFormatter()

    public init(viewModel: OnboardingViewModel, onBack: @escaping () -> Void, onImportCSV: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onBack = onBack
        self.onImportCSV = onImportCSV
    }

    public var body: some View {
        KWScreen(bottom: 40) {
            VStack(alignment: .leading, spacing: KWSpacing.md) {
                KWFlowHeader(.back, progress: (3, 2), action: onBack)
                OnboardingHeading(
                    title: "Agrega tus cuentas",
                    message: "Con su saldo de hoy. Las tarjetas de crédito empiezan con lo que debes.",
                )
                HStack(spacing: KWSpacing.xs) {
                    tile(.bank, "Banco") { editing = viewModel.newAccount(.bank) }
                    tile(.creditCard, "Tarjeta de crédito") { editing = viewModel.newAccount(.credit) }
                    tile(.cash, "Efectivo") { editing = viewModel.newAccount(.cash) }
                }
                KWGroupedCard(verticalPadding: KWSpacing.xxs) {
                    ForEach(viewModel.accounts) { account in
                        Button { editing = account } label: { row(account) }
                            .buttonStyle(.plain)
                    }
                }
                Text("Podrás vincular más tarjetas y agregar adicionales después.")
                    .font(KWTextStyle.caption.font)
                    .foregroundStyle(KWColor.Text.muted)
                Spacer(minLength: 0)
                Button("Continuar") { viewModel.continueFromAccounts() }
                    .buttonStyle(.kw())
                Button("Importar movimientos desde CSV", action: onImportCSV)
                    .buttonStyle(KWButtonStyle(.plain, size: .text, height: 40))
            }
        }
        .sheet(item: $editing) { draft in
            AccountFormView(
                draft: draft,
                principal: viewModel.principal,
                second: viewModel.second,
                isNew: !viewModel.accounts.contains { $0.id == draft.id },
                onSave: { viewModel.save($0)
                    editing = nil
                },
                onRemove: { viewModel.removeAccount(id: draft.id)
                    editing = nil
                },
                onClose: { editing = nil },
            )
        }
    }

    private func tile(_ icon: KWIcon, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: KWSpacing.xs) {
                KWIconView(icon, size: 24)
                Text(title).font(.kw(13, weight: 600, relativeTo: .footnote))
            }
            .foregroundStyle(KWColor.Text.primary)
            .frame(maxWidth: .infinity)
            .frame(height: 92)
            .background(KWColor.Surface.surface, in: RoundedRectangle(cornerRadius: KWRadius.card))
        }
        .buttonStyle(.plain)
    }

    private func row(_ account: OnboardingAccountDraft) -> some View {
        HStack(spacing: KWSpacing.sm) {
            leadingIcon(account)
            KWTitleSubtitle(account.displayName.isEmpty ? "Cuenta" : account.displayName, subtitle: subtitle(account))
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(formatter.number(account.kind == .credit && account.debtMode == .second ? account.secondBalance : account.balance))
                .font(.kw(15, weight: 700))
                .monospacedDigit()
                .foregroundStyle(account.kind == .credit ? KWColor.State.negative : KWColor.Text.primary)
        }
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func leadingIcon(_ account: OnboardingAccountDraft) -> some View {
        switch account.kind {
        case .cash:
            KWIconView(.cash, size: 20)
                .foregroundStyle(KWColor.Text.onPositive)
                .frame(width: 40, height: 40)
                .background(KWColor.State.positive, in: Circle())
        case .bank:
            Text(Self.initials(account.bank ?? account.name))
                .font(.kw(13, weight: 800, relativeTo: .footnote))
                .frame(width: 40, height: 40)
                .background(KWColor.Surface.surface2, in: Circle())
        case .credit:
            KWMiniCard(.solid(KWColor.Brand.b500), size: .tiny)
        }
    }

    private func subtitle(_ account: OnboardingAccountDraft) -> String {
        switch account.kind {
        case .cash:
            return "\(account.currency) · ya incluida"
        case .bank:
            let debit = account.lastFour.map { $0.isEmpty ? "" : " · Débito ··\($0)" } ?? ""
            return "Banco · \(account.currency)\(debit)"
        case .credit:
            let currencies = switch account.debtMode {
            case .dual: [viewModel.second, viewModel.principal].compactMap(\.self).joined(separator: " y ")
            case .second: viewModel.second ?? viewModel.principal
            default: viewModel.principal
            }
            return "Crédito · \(currencies)"
        }
    }

    /// First letters of the first two words ("Banco Uno" → "BU"), or the first two letters.
    static func initials(_ name: String) -> String {
        let words = name.split(separator: " ")
        let letters = words.count > 1 ? words.prefix(2).compactMap(\.first).map(String.init).joined() : String(name.prefix(2))
        return letters.uppercased()
    }
}
