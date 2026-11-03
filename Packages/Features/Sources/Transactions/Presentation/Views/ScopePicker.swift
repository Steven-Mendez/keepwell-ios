import DesignSystem
import Domain
import SharedPresentation
import SwiftUI
import TransactionsDomain

/// The first chip of the list: which account or card it shows. Filled white while narrowed, with
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
            .accessibilityHint(Text("Choose which account or card to show", bundle: #bundle))
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
        .foregroundStyle(isFiltered ? Color.black : KWColor.Text.secondary)
        .background(isFiltered ? Color.white : KWColor.Surface.surface, in: Capsule())
        .animation(.snappy, value: isFiltered)
    }
}

/// Picks the account or card the list shows, Revolut-style: "All accounts" first, then each
/// account followed by its plastics, in the Accounts tab's order.
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
                ForEach(viewModel.scopeGroups) { group in
                    KWGroupedCard(verticalPadding: KWSpacing.xxs) {
                        row(CardDisplay.name(of: group.account), subtitle: kindTitle(group.account.kind), scope: .account(group.id)) {
                            leadingIcon(icon(for: group.account.kind))
                        }
                        ForEach(group.cards) { card in
                            row(viewModel.cardTitle(card, in: group), subtitle: nil, scope: .card(card.id)) {
                                KWMiniCard(CardDisplay.miniCard(for: card), size: .tiny)
                            }
                            .padding(.leading, KWSpacing.lg)
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

    private func icon(for kind: AccountKind) -> KWIcon {
        switch kind {
        case .deposit: .bank
        case .cash: .cash
        case .credit: .creditCard
        }
    }

    private func kindTitle(_ kind: AccountKind) -> String {
        switch kind {
        case .deposit: String(localized: "Bank account", bundle: #bundle)
        case .cash: String(localized: "Cash", bundle: #bundle)
        case .credit: String(localized: "Credit card", bundle: #bundle)
        }
    }
}
