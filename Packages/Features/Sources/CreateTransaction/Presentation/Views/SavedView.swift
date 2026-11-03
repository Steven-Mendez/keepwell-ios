import CreateTransactionDomain
import DesignSystem
import Domain
import SharedPresentation
import SwiftUI

/// Step 5 · Saved: what was saved, the rate used and the new balance.
public struct SavedView: View {
    private let viewModel: CreateTransactionViewModel
    private let onClose: () -> Void

    public init(viewModel: CreateTransactionViewModel, onClose: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onClose = onClose
    }

    public var body: some View {
        KWScreen(bottom: 34) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Spacer()
                    KWCircleButton(.close, accessibilityLabel: String(localized: "Close", bundle: #bundle), action: onClose)
                }
                if let saved = viewModel.saved {
                    header(saved)
                    KWGroupedCard {
                        KWValueRow(
                            String(localized: "Status", bundle: #bundle),
                            value: saved.transaction.isConfirmed
                                ? String(localized: "Confirmed", bundle: #bundle)
                                : String(localized: "Planned", bundle: #bundle),
                            valueColor: saved.transaction.isConfirmed ? KWColor.State.positive : KWColor.State.pending,
                        )
                        KWValueRow(String(localized: "Method", bundle: #bundle), value: viewModel.sourceTitle ?? "—")
                        if let category = viewModel.category {
                            KWValueRow(String(localized: "Category", bundle: #bundle), value: CategoryDisplay.name(of: category))
                        }
                    }
                    KWGroupedCard {
                        ForEach(viewModel.savedRows(saved), id: \.label) { row in
                            KWValueRow(row.label, value: row.value)
                        }
                    }
                    if let total = viewModel.categoryTotalRow(saved) {
                        KWGroupedCard {
                            KWValueRow(total.label, value: total.value)
                        }
                    }
                }
                Spacer(minLength: 0)
                HStack(spacing: 10) {
                    Button { Task { await viewModel.startOver() } } label: { Text("Log another", bundle: #bundle) }
                        .buttonStyle(.kw(.surface, size: .regular))
                    Button(action: onClose) { Text("Done", bundle: #bundle) }
                        .buttonStyle(.kw(.primary, size: .regular))
                }
            }
        }
    }

    private func header(_ saved: SavedTransaction) -> some View {
        HStack(alignment: .top, spacing: KWSpacing.sm) {
            VStack(alignment: .leading, spacing: KWSpacing.xxs) {
                Text(viewModel.reviewAmount)
                    .font(.kw(40, weight: 800, relativeTo: .largeTitle))
                    .tracking(-1)
                    .monospacedDigit()
                Text(saved.transaction.description).font(.kw(17, weight: 600))
                Text(verbatim: "\(viewModel.dayLabel(saved.transaction.date)) · \(viewModel.timeLabel(saved.transaction.date))")
                    .font(KWTextStyle.label.font.weight(.regular))
                    .foregroundStyle(KWColor.Text.muted)
            }
            Spacer()
            KWIconView(.check, size: 26, lineWidth: 2.6)
                .foregroundStyle(KWColor.Text.onPositive)
                .frame(width: 52, height: 52)
                .background(KWColor.State.positive, in: Circle())
        }
    }
}
