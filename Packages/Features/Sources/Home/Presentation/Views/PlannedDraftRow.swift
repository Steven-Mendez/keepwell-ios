import DesignSystem
import Domain
import SharedPresentation
import SwiftUI

/// One draft on home with its Confirm button, and Discard for a draft an assistant recorded.
struct PlannedDraftRow: View {
    let viewModel: HomeViewModel
    let transaction: Domain.Transaction
    let display: TransactionDisplay

    var body: some View {
        KWTransactionRow(.planned, title: transaction.description, subtitle: display.subtitle(of: transaction)) {
            if transaction.source == .mcp, viewModel.canDiscardDrafts {
                Button {
                    Task { await viewModel.discardDraft(transaction) }
                } label: {
                    Text("Discard", bundle: #bundle)
                }
                .buttonStyle(.kw(.secondary, size: .mini))
            }
            Button {
                Task { await viewModel.confirm(transaction.id) }
            } label: {
                Text("Confirm", bundle: #bundle)
            }
            .buttonStyle(.kw(.primary, size: .mini))
            .disabled(viewModel.confirming.contains(transaction.id))
        }
        .padding(.vertical, -KWSpacing.sm)
    }
}
