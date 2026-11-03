import DesignSystem
import SwiftUI

/// Stands in for tabs whose screen hasn't been built yet, so they never show a blank screen.
/// Without movements it shows the real empty state and offers to log one; with movements it
/// says the screen is on its way instead of claiming there's no data.
struct PendingTabView: View {
    let tab: MainTab
    let hasMovements: Bool
    let onNewMovement: () -> Void

    var body: some View {
        KWScreen(bottom: KWSpacing.md) {
            VStack(spacing: 0) {
                KWLargeTitleHeader(title) {
                    if tab == .transactions {
                        KWCircleButton(
                            .plus,
                            style: .white,
                            accessibilityLabel: String(localized: "New transaction"),
                            action: onNewMovement,
                        )
                    }
                }
                Spacer(minLength: KWSpacing.md)
                if hasMovements {
                    KWEmptyState(
                        icon: icon,
                        title: String(localized: "Screen on its way"),
                        message: String(localized: "This section is still being built. Your transactions are already saved."),
                    )
                } else {
                    KWEmptyState(
                        icon: icon,
                        title: emptyTitle,
                        message: emptyMessage,
                        actionTitle: String(localized: "Log transaction"),
                        action: onNewMovement,
                    )
                }
                Spacer(minLength: KWSpacing.md)
            }
        }
    }

    private var title: String {
        switch tab {
        case .home: String(localized: "Home")
        case .transactions: String(localized: "Transactions")
        case .accounts: String(localized: "Accounts")
        case .summary: String(localized: "Summary")
        }
    }

    private var icon: KWIcon {
        switch tab {
        case .home: .home
        case .transactions: .list
        case .accounts: .tabAccounts
        case .summary: .chartBars
        }
    }

    private var emptyTitle: String {
        tab == .summary ? String(localized: "Your summary starts with one transaction") : String(localized: "No transactions yet")
    }

    private var emptyMessage: String {
        switch tab {
        case .summary:
            String(localized: "Once you log expenses and income, you will see what came in, what went out and what you spent it on.")
        case .home: String(localized: "Log your first expense, income or transfer and you will see your month here.")
        case .transactions, .accounts: String(localized: "Log your first expense, income or transfer and it shows up here.")
        }
    }
}
