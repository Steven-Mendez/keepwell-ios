import DesignSystem
import Domain
import SettingsDomain
import SharedPresentation
import SwiftUI

/// Settings › Payment methods: each account with its card and transfer channel. A card opens its
/// own screen, where its name, color, product and expiry are edited.
public struct PaymentMethodsView: View {
    private let viewModel: PaymentMethodsViewModel
    private let onBack: () -> Void
    private let onOpenAccount: (Account) -> Void

    public init(viewModel: PaymentMethodsViewModel, onBack: @escaping () -> Void, onOpenAccount: @escaping (Account) -> Void) {
        self.viewModel = viewModel
        self.onBack = onBack
        self.onOpenAccount = onOpenAccount
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KWSpacing.md) {
                KWNavigationHeader(String(localized: "Payment methods", bundle: #bundle), style: .large, onBack: onBack)
                if viewModel.hasFailed {
                    Text("We couldn't load your payment methods.", bundle: #bundle)
                        .foregroundStyle(KWColor.Text.muted)
                } else if viewModel.groups.isEmpty {
                    Text("Add a bank account or a card from Accounts to see it here.", bundle: #bundle)
                        .font(KWTextStyle.label.font.weight(.regular))
                        .foregroundStyle(KWColor.Text.muted)
                }
                ForEach(viewModel.groups) { group in
                    VStack(alignment: .leading, spacing: KWSpacing.sm) {
                        KWSectionHeader(viewModel.title(of: group))
                        KWGroupedCard {
                            ForEach(group.methods) { card in
                                row(card, in: group)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, KWLayout.gutter)
            .padding(.top, KWLayout.safeTop)
            .padding(.bottom, KWSpacing.xxl)
        }
        .scrollIndicators(.hidden)
        .ignoresSafeArea(edges: .top)
        .background(KWColor.Surface.bg)
        .foregroundStyle(KWColor.Text.primary)
        .toolbar(.hidden, for: .navigationBar)
        .task { await viewModel.load() }
    }

    @ViewBuilder
    private func row(_ card: Card, in group: PaymentMethodGroup) -> some View {
        let subtitle = viewModel.subtitle(of: card)
        let content = HStack(spacing: KWSpacing.sm) {
            KWMiniCard(CardDisplay.miniCard(for: card))
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.title(of: card, in: group))
                    .font(.kw(15, weight: 600))
                    .lineLimit(1)
                Text(subtitle.text)
                    .font(KWTextStyle.captionSm.font.weight(.regular))
                    .foregroundStyle(subtitle.isWarning ? KWColor.State.negative : KWColor.Text.muted)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if viewModel.opensScreen(card) {
                KWIconView(.chevronRight, size: 16)
                    .foregroundStyle(KWColor.Text.faint)
            }
        }
        .padding(.vertical, KWSpacing.sm)
        .frame(minHeight: KWLayout.minTouch)
        .contentShape(Rectangle())
        if viewModel.opensScreen(card) {
            Button { onOpenAccount(group.account) } label: { content }
                .buttonStyle(.plain)
        } else {
            content
                .accessibilityElement(children: .combine)
        }
    }
}
