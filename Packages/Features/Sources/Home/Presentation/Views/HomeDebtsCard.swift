import DesignSystem
import Domain
import HomeDomain
import SwiftUI

/// The way into debts, always on home so there's a place to add the first one. It shows the next
/// loan installment and what the person owes and is owed, one amount per currency.
struct HomeDebtsCard: View {
    let viewModel: HomeViewModel
    let overview: HomeOverview
    let hidesBalances: Bool
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: KWSpacing.sm) {
                HStack {
                    Text("Debts", bundle: #bundle)
                        .font(KWTextStyle.heading.font)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    Text("See all", bundle: #bundle)
                        .font(KWTextStyle.label.font)
                        .foregroundStyle(KWColor.Brand.link)
                }
                let owe = viewModel.debtTotal(overview.debtTotals.youOwe, hidden: hidesBalances)
                let owed = viewModel.debtTotal(overview.debtTotals.owedToYou, hidden: hidesBalances)
                if owe == nil, owed == nil {
                    Text("No debts yet", bundle: #bundle)
                        .font(KWTextStyle.caption.font.weight(.regular))
                        .foregroundStyle(KWColor.Text.muted)
                } else {
                    if let loan = viewModel.nextLoan(overview), let line = viewModel.installmentLine(loan, hidden: hidesBalances) {
                        Text(line)
                            .font(KWTextStyle.caption.font.weight(.regular))
                            .foregroundStyle(loan.isNextOverdue ? KWColor.State.pending : KWColor.Text.secondary)
                            .monospacedDigit()
                            .lineLimit(2)
                    }
                    HStack(alignment: .top, spacing: KWSpacing.md) {
                        total(String(localized: "You owe", bundle: #bundle), value: owe, color: KWColor.State.negative)
                        total(String(localized: "Owed to you", bundle: #bundle), value: owed, color: KWColor.State.positive)
                    }
                }
            }
            .padding(KWSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(KWColor.Surface.surface, in: RoundedRectangle(cornerRadius: KWRadius.surface, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    private func total(_ title: String, value: String?, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(KWTextStyle.captionSm.font).foregroundStyle(KWColor.Text.muted)
            Text(value ?? "—")
                .font(.kw(15, weight: 600))
                .foregroundStyle(value == nil ? KWColor.Text.muted : color)
                .monospacedDigit()
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
