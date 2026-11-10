import SwiftUI
import Testing
@testable import DesignSystem

/// The components in light mode. Their dark references live in the other suites and must not
/// change; these pin how the light palette lands on the same compositions.
@Suite("Light mode snapshots")
@MainActor
struct LightModeSnapshotTests {
    @Test
    func buttons() {
        let view = VStack(spacing: KWSpacing.sm) {
            Button("Continue") {}.buttonStyle(.kw())
            Button("ATM withdrawal") {}.buttonStyle(.kw(.secondary))
            Button("Log another") {}.buttonStyle(.kw(.surface, size: .regular))
            Button("Delete account") {}.buttonStyle(.kw(.destructive, size: .row))
            Button("Complete card details") {}.buttonStyle(.kw(.link, size: .medium))
            Button("Not now") {}.buttonStyle(.kw(.plain, size: .text))
            Button("Disabled") {}.buttonStyle(.kw()).disabled(true)
        }
        .padding(KWLayout.gutter)
        assertComponentSnapshot(of: view, height: 440, named: "light", colorScheme: .light)
    }

    @Test
    func chipsAndSegmentedControls() {
        let view = VStack(alignment: .leading, spacing: KWSpacing.md) {
            HStack(spacing: KWSpacing.xs) {
                KWChip("All", isSelected: true) {}
                KWChip("Expenses", isSelected: false) {}
                KWChip("Groceries", isSelected: true, style: .extra) {}
            }
            HStack(spacing: KWSpacing.xs) {
                KWChip("NIO · Córdoba", isSelected: true, style: .outlined, height: 38) {}
                KWChip("EUR · Euro", isSelected: false, style: .outlined, height: 38) {}
            }
            KWSegmentedControl(
                [(value: 0, title: "Expense"), (value: 1, title: "Income"), (value: 2, title: "Transfer")],
                selection: .constant(0),
            )
            KWSegmentedControl([(value: 0, title: "NIO"), (value: 1, title: "USD")], selection: .constant(0), style: .accent)
        }
        .padding(KWLayout.gutter)
        .frame(maxWidth: .infinity, alignment: .leading)
        assertComponentSnapshot(of: view, height: 260, named: "light", colorScheme: .light)
    }

    @Test
    func headers() {
        let view = VStack(spacing: KWSpacing.xl) {
            KWFlowHeader(.back, progress: (3, 2)) {}
            KWLargeTitleHeader("Transactions") {
                KWCircleButton(.plus, style: .white, accessibilityLabel: "New transaction") {}
            }
            KWNavigationHeader("Mastercard ··1234", buttonStyle: .translucent) {}
            KWNavigationHeader("Settings", style: .large) {}
        }
        .padding(KWLayout.gutter)
        assertComponentSnapshot(of: view, height: 300, named: "light", colorScheme: .light)
    }

    @Test
    func actionsTogglesAndProgress() {
        let view = VStack(spacing: KWSpacing.md) {
            HStack(spacing: KWSpacing.xs) {
                KWActionButton("Pay", icon: .arrowUp, style: .prominent) {}
                KWActionButton("Edit name", icon: .pencil) {}
                KWActionButton("Color", icon: .droplet, style: .active) {}
            }
            Toggle("iCloud backup", isOn: .constant(true)).toggleStyle(.kw)
            Toggle("Hide amounts on exit", isOn: .constant(false)).toggleStyle(.kw)
            KWProgressBar(0.54, fill: KWColor.State.extra)
            KWProgressBar(0.29, fill: KWColor.Brand.accent, height: 8)
            KWSwipeToConfirm("Slide to save expense") {}
            KWPasscodeDots(length: 6, filled: 2)
        }
        .font(KWTextStyle.body.font)
        .foregroundStyle(KWColor.Text.primary)
        .padding(KWLayout.gutter)
        assertComponentSnapshot(of: view, height: 420, named: "light", colorScheme: .light)
    }

    @Test
    func listAndTransactionRows() {
        let view = VStack(alignment: .leading, spacing: KWSpacing.xs) {
            KWSectionHeader("Currency")
            KWGroupedCard {
                KWValueRow("Main currency", value: "USD · US dollar ›", style: .setting, verticalPadding: 14)
                KWValueRow("Status", value: "Confirmed", valueColor: KWColor.State.positive)
            }
            KWGroupedCard(horizontalPadding: 14, verticalPadding: 4) {
                KWTransactionRow(
                    .planned,
                    title: "Rent",
                    subtitle: "Housing · Debit 1234",
                    amount: "−C$3,500.00",
                    secondaryAmount: "≈ $95.56",
                )
                KWTransactionRow(.expense, title: "Dinner", subtitle: "Restaurants · Cash", amount: "−C$250.00", secondaryAmount: "$6.83")
                KWTransactionRow(.income, title: "Interest", subtitle: "Interest · Savings", amount: "+$3.02", secondaryAmount: "C$110.61")
                KWTransactionRow(.planned, title: "Food", subtitle: "Groceries · Debit 1234") {
                    Button("Confirm") {}.buttonStyle(.kw(.primary, size: .mini))
                }
            }
        }
        .padding(KWLayout.gutter)
        assertComponentSnapshot(of: view, height: 470, named: "light", colorScheme: .light)
    }

    /// The colored logo on light, next to the icon tile, which keeps its white-on-blue look.
    @Test
    func logoOnLight() {
        let view = VStack(spacing: KWSpacing.xl) {
            KWAppIconTile()
            KWWordmark()
            KWLogoMark(size: 40).foregroundStyle(KWColor.Semantic.logo)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        assertComponentSnapshot(of: view, height: 280, named: "light", colorScheme: .light)
    }

    /// Glows turn into pale tints; the brand gradient (dark splash) is unchanged.
    @Test
    func glowBackgrounds() {
        let view = HStack(spacing: 0) {
            KWGlowBackground(.brand)
            KWGlowBackground(.success)
            KWGlowBackground(.navy)
        }
        assertComponentSnapshot(of: view, height: 400, named: "light", colorScheme: .light)
    }

    /// Card art keeps its own colors and ink in light mode.
    @Test
    func cardArtIsUnchanged() {
        let view = VStack(spacing: KWSpacing.md) {
            KWCardArt(palette: .grafito, bank: "Bank Two", holder: "Steven", lastFour: "1234", kindLabel: "Debit")
            KWCardArt(palette: .lima, bank: "Wallet", holder: "Steven", lastFour: "5678", kindLabel: "Cash")
        }
        .padding(KWLayout.gutter)
        assertComponentSnapshot(of: view, height: 520, named: "light", colorScheme: .light)
    }
}
