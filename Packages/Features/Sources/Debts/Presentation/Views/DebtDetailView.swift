import Core
import DebtsDomain
import DesignSystem
import Domain
import SharedPresentation
import SwiftUI

/// One personal debt: what is left, repayments, and settling.
struct DebtDetailView: View {
    @Bindable var viewModel: DebtDetailViewModel
    let hidesBalances: Bool
    let onEdit: () -> Void
    let onDone: () -> Void
    let onClose: () -> Void
    @State private var isConfirmingDelete = false
    /// The repayment waiting for "Delete" to be confirmed.
    @State private var deletingRepayment: DebtRepayment?

    var body: some View {
        VStack(alignment: .leading, spacing: KWSpacing.md) {
            KWFlowHeader(.close, action: onClose)
            HStack(alignment: .firstTextBaseline) {
                Text(viewModel.title).kwTextStyle(.titleSm).accessibilityAddTraits(.isHeader)
                Spacer()
                Button(action: onEdit) {
                    Text("Edit", bundle: #bundle).font(KWTextStyle.label.font).foregroundStyle(KWColor.Brand.link)
                }
                .buttonStyle(.plain)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: KWSpacing.md) {
                    summary
                    if !viewModel.debt.isSettled {
                        repayment
                    }
                    if !viewModel.debt.repayments.isEmpty {
                        KWSectionHeader(String(localized: "Repayments", bundle: #bundle))
                        KWGroupedCard {
                            ForEach(viewModel.debt.repayments, id: \.id) { repayment in
                                repaymentRow(repayment)
                            }
                        }
                        Text("Touch and hold a repayment to delete it.", bundle: #bundle)
                            .font(KWTextStyle.captionSm.font.weight(.regular))
                            .foregroundStyle(KWColor.Text.muted)
                    }
                    actions
                }
                .padding(.bottom, KWSpacing.md)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.immediately)
        }
        .padding(.horizontal, KWLayout.gutter)
        .padding(.top, KWSpacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(KWColor.Surface.bg)
        .foregroundStyle(KWColor.Text.primary)
        .confirmationDialog(
            String(localized: "Delete this debt?", bundle: #bundle),
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible,
        ) {
            Button(role: .destructive) {
                Task {
                    if await viewModel.delete() {
                        onDone()
                    }
                }
            } label: {
                Text("Delete", bundle: #bundle)
            }
            Button(role: .cancel) {} label: {
                Text("Cancel", bundle: #bundle)
            }
        } message: {
            if viewModel.debt.repayments.contains(where: { $0.transactionID != nil }) {
                Text("Repayments you deposited stay as movements in their accounts.", bundle: #bundle)
            }
        }
        .confirmationDialog(
            String(localized: "Delete this repayment?", bundle: #bundle),
            isPresented: Binding(get: { deletingRepayment != nil }, set: {
                if !$0 {
                    deletingRepayment = nil
                }
            }),
            titleVisibility: .visible,
            presenting: deletingRepayment,
        ) { repayment in
            Button(role: .destructive) {
                Task { await viewModel.deleteRepayment(repayment) }
            } label: {
                Text("Delete", bundle: #bundle)
            }
        } message: { repayment in
            if repayment.transactionID != nil {
                Text("The income it deposited is deleted too, and the balance goes back.", bundle: #bundle)
            }
        }
        .task { await viewModel.load() }
    }

    private func repaymentRow(_ repayment: DebtRepayment) -> some View {
        KWValueRow(viewModel.repaymentTitle(repayment), value: viewModel.amount(repayment.amount, hidden: hidesBalances))
            .contentShape(Rectangle())
            .contextMenu {
                Button(role: .destructive) { deletingRepayment = repayment } label: {
                    Label { Text("Delete repayment", bundle: #bundle) } icon: { Image(systemName: "trash") }
                }
            }
            .accessibilityActions {
                Button { deletingRepayment = repayment } label: { Text("Delete repayment", bundle: #bundle) }
            }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: KWSpacing.xs) {
            Text(viewModel.summary(hidden: hidesBalances))
                .font(.kw(17, weight: 700))
                .monospacedDigit()
            Text(viewModel.day(viewModel.debt.date) + (viewModel.debt.note.map { " · \($0)" } ?? ""))
                .font(KWTextStyle.caption.font)
                .foregroundStyle(KWColor.Text.muted)
            if let settled = viewModel.debt.settledAt {
                Text("Settled on \(viewModel.day(settled))", bundle: #bundle)
                    .font(KWTextStyle.caption.font)
                    .foregroundStyle(KWColor.State.positive)
            }
            if let due = viewModel.due {
                DebtDueText(line: due)
            }
            trackingNote
                .font(KWTextStyle.captionSm.font.weight(.regular))
                .foregroundStyle(KWColor.Text.muted)
        }
        .padding(KWSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(KWColor.Surface.surface, in: RoundedRectangle(cornerRadius: KWRadius.surface, style: .continuous))
    }

    /// Only a debt owed to the person can have its repayments deposited, so only its note says so.
    private var trackingNote: Text {
        viewModel.debt.direction == .theyOweMe
            ? Text("Only tracked here: it doesn't change your balances unless you deposit a repayment into an account.", bundle: #bundle)
            : Text("Only tracked here: it doesn't record a movement or change your balances.", bundle: #bundle)
    }

    private var repayment: some View {
        VStack(alignment: .leading, spacing: KWSpacing.xs) {
            KWGroupedCard {
                KWAmountFieldRow(
                    String(localized: "Amount paid back", bundle: #bundle),
                    symbol: CurrencyFormatter.symbol(for: viewModel.debt.amount.currency),
                    text: $viewModel.repaymentText,
                )
            }
            if viewModel.canDeposit {
                KWGroupedCard {
                    Menu {
                        ForEach(viewModel.depositOptions, id: \.id) { option in
                            Button(option.title) { viewModel.depositAccountID = option.id }
                        }
                    } label: {
                        KWValueRow(
                            String(localized: "Deposit into account", bundle: #bundle),
                            value: "\(viewModel.depositTitle) ›",
                            verticalPadding: 14,
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                if let note = viewModel.depositNote {
                    Text(note)
                        .font(KWTextStyle.captionSm.font.weight(.regular))
                        .foregroundStyle(KWColor.Text.muted)
                }
            }
            if let error = viewModel.repaymentError {
                Text(error).font(KWTextStyle.caption.font).foregroundStyle(KWColor.State.negative)
            }
            Button {
                KWKeyboard.dismiss()
                Task { await viewModel.repay() }
            } label: {
                Text("Record repayment", bundle: #bundle)
            }
            .buttonStyle(.kw())
            .disabled(!viewModel.canRepay)
        }
    }

    private var actions: some View {
        VStack(spacing: KWSpacing.xs) {
            if viewModel.debt.isSettled {
                if viewModel.debt.remaining > 0 {
                    Button {
                        Task { await viewModel.reopen() }
                    } label: {
                        Text("Reopen", bundle: #bundle)
                    }
                    .buttonStyle(.kw(.surface, size: .row))
                }
            } else {
                Button {
                    Task { await viewModel.settle() }
                } label: {
                    Text("Mark as settled", bundle: #bundle)
                }
                .buttonStyle(.kw(.surface, size: .row))
            }
            Button { isConfirmingDelete = true } label: {
                Text("Delete debt", bundle: #bundle)
            }
            .buttonStyle(.kw(.destructive, size: .row))
        }
    }
}
