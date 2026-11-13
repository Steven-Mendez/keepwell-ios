import DesignSystem
import Domain
import SharedPresentation
import SwiftUI
import TransactionsDomain

/// The first chip of the list: which account it shows. Filled white while narrowed, with
/// its own ✕, so a list opened from a card always says so and clears in one tap.
struct ScopeChip: View {
    let title: String
    let isFiltered: Bool
    let onPick: () -> Void
    let onClear: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onPick) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(KWTextStyle.label.font)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                }
                .padding(.leading, KWSpacing.md)
                .padding(.trailing, isFiltered ? KWSpacing.xxs : KWSpacing.md)
                .frame(height: KWComponentMetrics.chipHeight)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Accounts: \(title)", bundle: #bundle))
            .accessibilityHint(Text("Choose which account to show", bundle: #bundle))
            if isFiltered {
                Button(action: onClear) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 32, height: KWComponentMetrics.chipHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Show all accounts", bundle: #bundle))
            }
        }
        .foregroundStyle(isFiltered ? KWColor.Semantic.primaryForeground : KWColor.Text.secondary)
        .background(isFiltered ? KWColor.Semantic.primary : KWColor.Surface.surface, in: Capsule())
        .animation(.snappy, value: isFiltered)
    }
}

/// Picks the account the list shows, Revolut-style: "All accounts" first, then one row per account,
/// each with its card, in the Accounts tab's order.
struct ScopePickerSheet: View {
    let viewModel: TransactionsViewModel
    let onClose: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KWSpacing.md) {
                KWFlowHeader(.close, action: onClose)
                Text("Show movements from", bundle: #bundle)
                    .kwTextStyle(.titleSm)
                    .accessibilityAddTraits(.isHeader)
                KWGroupedCard(verticalPadding: KWSpacing.xxs) {
                    row(
                        String(localized: "All accounts", bundle: #bundle),
                        subtitle: nil,
                        scope: .all,
                    ) { leadingIcon(.wallet) }
                }
                if !viewModel.scopeOptions.isEmpty {
                    KWGroupedCard(verticalPadding: KWSpacing.xxs) {
                        ForEach(viewModel.scopeOptions) { option in
                            row(CardDisplay.name(of: option.account), subtitle: subtitle(option), scope: .account(option.id)) {
                                leading(option)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, KWLayout.gutter)
            .padding(.vertical, KWSpacing.xl)
        }
        .scrollIndicators(.hidden)
        .foregroundStyle(KWColor.Text.primary)
    }

    private func row(_ title: String, subtitle: String?, scope: TransactionScope, @ViewBuilder leading: () -> some View) -> some View {
        let isSelected = viewModel.scope == scope
        return Button {
            viewModel.scope = scope
            onClose()
        } label: {
            HStack(spacing: KWSpacing.sm) {
                leading()
                KWTitleSubtitle(title, subtitle: subtitle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if isSelected {
                    KWIconView(.check, size: 18)
                        .foregroundStyle(KWColor.Brand.link)
                }
            }
            .padding(.vertical, KWSpacing.sm)
            .frame(minHeight: KWLayout.minTouch)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func leadingIcon(_ icon: KWIcon) -> some View {
        KWIconView(icon, size: 18)
            .frame(width: 36, height: 36)
            .background(KWColor.Surface.surface2, in: Circle())
            .frame(width: 40)
    }

    /// The account's card, as on the Accounts tab; cash keeps its banknote icon.
    @ViewBuilder
    private func leading(_ option: TransactionScopeOption) -> some View {
        if let card = option.card {
            KWMiniCard(CardDisplay.miniCard(for: card), size: .tiny).frame(width: 40)
        } else {
            leadingIcon(option.account.kind == .cash ? .cash : .bank)
        }
    }

    /// "Bank account · •••• 1234": the kind, and the digits that tell two cards of a bank apart.
    /// Closed accounts say so, at the end of the list (`scopeOptions`).
    private func subtitle(_ option: TransactionScopeOption) -> String {
        let kind = kindTitle(option.account.kind)
        let closed = option.account.isOpen ? "" : " · \(AccountClosingText.closed)"
        guard let digits = option.card?.lastFour else { return kind + closed }
        return "\(kind) · •••• \(digits)\(closed)"
    }

    private func kindTitle(_ kind: AccountKind) -> String {
        switch kind {
        case .deposit: String(localized: "Bank account", bundle: #bundle)
        case .cash: String(localized: "Cash", bundle: #bundle)
        case .credit: String(localized: "Credit card", bundle: #bundle)
        }
    }
}
