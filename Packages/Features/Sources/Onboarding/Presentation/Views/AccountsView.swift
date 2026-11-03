import Core
import DesignSystem
import OnboardingDomain
import SwiftUI

/// Step 4 · Accounts.
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
                KWFlowHeader(.back, progress: (5, 3), action: onBack)
                OnboardingHeading(
                    title: String(localized: "Add your accounts", bundle: #bundle),
                    message: String(localized: "With today's balance. Credit cards start with what you owe.", bundle: #bundle),
                )
                HStack(spacing: KWSpacing.xs) {
                    tile(.bank, String(localized: "Bank", bundle: #bundle)) { editing = viewModel.newAccount(.bank) }
                    tile(.creditCard, String(localized: "Credit card", bundle: #bundle)) { editing = viewModel.newAccount(.credit) }
                    tile(.cash, String(localized: "Cash", bundle: #bundle)) { editing = viewModel.newAccount(.cash) }
                }
                if !viewModel.accounts.isEmpty {
                    accountList
                    Text("Swipe an account left to remove it.", bundle: #bundle)
                        .font(KWTextStyle.caption.font)
                        .foregroundStyle(KWColor.Text.muted)
                }
                Spacer(minLength: 0)
                Button { viewModel.continueFromAccounts() } label: { Text("Continue", bundle: #bundle) }
                    .buttonStyle(.kw())
                Button(action: onImportCSV) { Text("Import transactions from CSV", bundle: #bundle) }
                    .buttonStyle(KWButtonStyle(.plain, size: .text, height: 40))
            }
        }
        .sheet(item: $editing) { draft in
            AccountFormView(
                draft: draft,
                principal: viewModel.principal,
                second: viewModel.second,
                cashCurrencies: viewModel.cashCurrencyOptions(for: draft),
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

    /// Built by hand rather than with `KWGroupedCard` so a swiped row's delete button reaches the
    /// card's edge and is clipped by its corners.
    private var accountList: some View {
        VStack(spacing: 0) {
            ForEach(Array(viewModel.accounts.enumerated()), id: \.element.id) { index, account in
                if index > 0 {
                    KWDivider().padding(.horizontal, KWSpacing.md)
                }
                Button { editing = account } label: { row(account) }
                    .buttonStyle(.plain)
                    .kwSwipeToDelete {
                        withAnimation(.snappy) { viewModel.removeAccount(id: account.id) }
                    }
            }
        }
        .padding(.vertical, KWSpacing.xxs)
        .background(KWColor.Surface.surface)
        .clipShape(RoundedRectangle(cornerRadius: KWRadius.surface, style: .continuous))
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
            KWTitleSubtitle(title(of: account), subtitle: subtitle(account))
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(formatter.number(account.kind == .credit && account.debtMode == .second ? account.secondBalance : account.balance))
                .font(.kw(15, weight: 700))
                .monospacedDigit()
                .foregroundStyle(account.kind == .credit ? KWColor.State.negative : KWColor.Text.primary)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, KWSpacing.md)
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

    private func title(of account: OnboardingAccountDraft) -> String {
        account.displayName.isEmpty ? String(localized: "Account", bundle: #bundle) : account.displayName
    }

    private func subtitle(_ account: OnboardingAccountDraft) -> String {
        switch account.kind {
        case .cash:
            let currency = account.currency
            return String(localized: "\(currency) · already included", bundle: #bundle)
        case .bank:
            let currency = account.currency
            guard let lastFour = account.lastFour, !lastFour.isEmpty else {
                return String(localized: "Bank · \(currency)", bundle: #bundle)
            }
            return String(localized: "Bank · \(currency) · Debit ··\(lastFour)", bundle: #bundle)
        case .credit:
            let principal = viewModel.principal
            switch account.debtMode {
            case .dual:
                guard let second = viewModel.second else { return String(localized: "Credit · \(principal)", bundle: #bundle) }
                return String(localized: "Credit · \(second) and \(principal)", bundle: #bundle)
            case .second:
                let currency = viewModel.second ?? principal
                return String(localized: "Credit · \(currency)", bundle: #bundle)
            default:
                return String(localized: "Credit · \(principal)", bundle: #bundle)
            }
        }
    }

    /// First letters of the first two words ("Bank One" → "BO"), or the first two letters.
    static func initials(_ name: String) -> String {
        let words = name.split(separator: " ")
        let letters = words.count > 1 ? words.prefix(2).compactMap(\.first).map(String.init).joined() : String(name.prefix(2))
        return letters.uppercased()
    }
}
