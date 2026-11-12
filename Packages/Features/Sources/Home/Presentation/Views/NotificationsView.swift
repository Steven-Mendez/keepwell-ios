import DesignSystem
import Domain
import SharedPresentation
import SwiftUI

/// "Notifications": what needs attention right now (payments, renewals, budgets…) and the rules an
/// assistant proposed. It keeps no read state: each line disappears when it stops applying.
public struct NotificationsView: View {
    private let viewModel: HomeViewModel
    private let onBack: () -> Void
    private let onOpen: (InboxItem.Destination) -> Void
    /// Fixed only in snapshots, where "what applies today" must not depend on when they run.
    private let now: Date
    /// The same eye as home: hiding amounts is about who's looking at the phone, on every screen.
    @AppStorage("home.hidesBalances") private var hidesBalances = false

    public init(
        viewModel: HomeViewModel,
        onBack: @escaping () -> Void,
        onOpen: @escaping (InboxItem.Destination) -> Void,
        now: Date = .now,
    ) {
        self.viewModel = viewModel
        self.onBack = onBack
        self.onOpen = onOpen
        self.now = now
    }

    public var body: some View {
        let items = viewModel.inbox(now: now, calendar: viewModel.calendar)
        let proposals = viewModel.overview?.proposedRules ?? []
        return ScrollView {
            VStack(alignment: .leading, spacing: KWSpacing.md) {
                KWNavigationHeader(String(localized: "Notifications", bundle: #bundle), style: .large, onBack: onBack)
                if viewModel.state == .failed {
                    Text("We couldn't load your notifications.", bundle: #bundle)
                        .foregroundStyle(KWColor.Text.muted)
                } else if viewModel.overview != nil, items.isEmpty, proposals.isEmpty {
                    KWEmptyState(
                        icon: .bell,
                        title: String(localized: "You're all caught up", bundle: #bundle),
                        message: String(localized: "Nothing needs your attention right now.", bundle: #bundle),
                    )
                    .padding(.vertical, KWSpacing.xl)
                } else {
                    if !proposals.isEmpty {
                        HomeProposedRulesCard(viewModel: viewModel, rules: proposals, hidesBalances: hidesBalances)
                    }
                    if !items.isEmpty {
                        KWGroupedCard(verticalPadding: 6) {
                            ForEach(items) { item in
                                row(item)
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
    private func row(_ item: InboxItem) -> some View {
        if let destination = item.destination {
            Button { onOpen(destination) } label: { content(item, showsChevron: true) }
                .buttonStyle(.plain)
        } else {
            content(item, showsChevron: false)
        }
    }

    private func color(_ tone: InboxItem.Tone) -> Color {
        switch tone {
        case .pending: KWColor.State.pending
        case .accent: KWColor.Brand.link
        case .negative: KWColor.State.negative
        }
    }

    private func content(_ item: InboxItem, showsChevron: Bool) -> some View {
        let tint = color(item.tone)
        return HStack(spacing: KWSpacing.sm) {
            Group {
                if let category = item.category {
                    CategorySymbol(category, size: 18)
                } else {
                    KWIconView(item.icon, size: 18)
                }
            }
            .foregroundStyle(tint)
            .frame(width: 36, height: 36)
            .background(tint.opacity(0.15), in: Circle())
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.kw(15, weight: 600, relativeTo: .subheadline))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                // The warning stays under "hide balances"; only the amounts in its detail go.
                if !(hidesBalances && item.bodyHasAmounts) {
                    Text(item.body)
                        .font(KWTextStyle.caption.font.weight(.regular))
                        .foregroundStyle(KWColor.Text.muted)
                        .multilineTextAlignment(.leading)
                        .monospacedDigit()
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            if showsChevron {
                KWIconView(.chevronRight, size: 16)
                    .foregroundStyle(KWColor.Text.muted)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, KWSpacing.sm)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
