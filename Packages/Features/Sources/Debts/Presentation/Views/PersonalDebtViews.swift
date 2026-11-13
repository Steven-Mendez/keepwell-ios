import Core
import DebtsDomain
import DesignSystem
import Domain
import SharedPresentation
import SwiftUI

/// The sheet to write down money lent or borrowed, or edit it.
struct DebtEditorView: View {
    @Bindable var viewModel: DebtEditorViewModel
    let onDone: () -> Void
    let onClose: () -> Void
    @State private var isConfirmingDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: KWSpacing.md) {
            KWFlowHeader(.close, action: onClose)
            Text(viewModel.title).kwTextStyle(.titleSm).accessibilityAddTraits(.isHeader)
            ScrollView {
                form.padding(.bottom, KWSpacing.md)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.immediately)
            if let error = viewModel.errorMessage {
                Text(error).font(KWTextStyle.caption.font).foregroundStyle(KWColor.State.negative)
            }
            Button {
                KWKeyboard.dismiss()
                Task {
                    if await viewModel.save() {
                        onDone()
                    }
                }
            } label: {
                Text("Save", bundle: #bundle)
            }
            .buttonStyle(.kw())
            .disabled(!viewModel.canSave)
        }
        .padding(.horizontal, KWLayout.gutter)
        .padding(.top, KWSpacing.xl)
        .padding(.bottom, KWSpacing.md)
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
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: KWSpacing.md) {
            KWSegmentedControl(viewModel.directionOptions, selection: $viewModel.direction)
            fields
            Text("Only tracked here: it doesn't record a movement or change your balances.", bundle: #bundle)
                .font(KWTextStyle.captionSm.font.weight(.regular))
                .foregroundStyle(KWColor.Text.muted)
            if !viewModel.isCreating {
                Button { isConfirmingDelete = true } label: {
                    Text("Delete debt", bundle: #bundle)
                }
                .buttonStyle(.kw(.destructive, size: .row))
                .padding(.top, KWSpacing.xs)
            }
        }
    }

    private var fields: some View {
        KWGroupedCard {
            KWTextFieldRow(
                String(localized: "Person", bundle: #bundle),
                placeholder: String(localized: "Juan", bundle: #bundle),
                text: $viewModel.person,
            )
            KWAmountFieldRow(
                String(localized: "Amount", bundle: #bundle),
                symbol: CurrencyFormatter.symbol(for: viewModel.currency),
                text: $viewModel.amountText,
            )
            if viewModel.isCreating, viewModel.currencyOptions.count > 1 {
                Menu {
                    ForEach(viewModel.currencyOptions, id: \.self) { code in
                        Button(code) { viewModel.currency = code }
                    }
                } label: {
                    KWValueRow(String(localized: "Currency", bundle: #bundle), value: "\(viewModel.currency) ›", verticalPadding: 14)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            DatePicker(selection: $viewModel.date, displayedComponents: [.date]) {
                Text("Date", bundle: #bundle).font(KWTextStyle.body.font).foregroundStyle(KWColor.Text.secondary)
            }
            .padding(.vertical, KWSpacing.xs)
            dueDateRows
            KWTextFieldRow(
                String(localized: "Note", bundle: #bundle),
                placeholder: String(localized: "Optional", bundle: #bundle),
                text: $viewModel.note,
            )
        }
    }
}

extension DebtEditorView {
    /// "Set a due date", and the day once it is on. Off saves the debt without one.
    @ViewBuilder
    private var dueDateRows: some View {
        Toggle(isOn: $viewModel.hasDueDate.animation(.snappy)) {
            Text("Set a due date", bundle: #bundle).font(KWTextStyle.body.font)
        }
        .toggleStyle(.kw)
        .padding(.vertical, 14)
        if viewModel.hasDueDate {
            DatePicker(selection: $viewModel.dueDate, in: viewModel.date..., displayedComponents: [.date]) {
                Text("Due date", bundle: #bundle).font(KWTextStyle.body.font).foregroundStyle(KWColor.Text.secondary)
            }
            .padding(.vertical, KWSpacing.xs)
        }
    }
}

/// "Due Nov 28, 2026", "Due today" or "Overdue · 3 days", in the negative color only when overdue.
struct DebtDueText: View {
    let line: DebtDueLine

    var body: some View {
        Text(line.text)
            .font(KWTextStyle.caption.font)
            .foregroundStyle(line.isOverdue ? KWColor.State.negative : KWColor.Text.muted)
    }
}

/// "Split" on an expense: each person and their share, equal by default.
public struct SplitBillView: View {
    @Bindable private var viewModel: SplitBillViewModel
    private let onDone: () -> Void
    private let onClose: () -> Void

    public init(viewModel: SplitBillViewModel, onDone: @escaping () -> Void, onClose: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onDone = onDone
        self.onClose = onClose
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: KWSpacing.md) {
            KWFlowHeader(.close, action: onClose)
            VStack(alignment: .leading, spacing: 2) {
                Text("Split the expense", bundle: #bundle).kwTextStyle(.titleSm).accessibilityAddTraits(.isHeader)
                Text(verbatim: "\(viewModel.transaction.description) · \(viewModel.total)")
                    .font(KWTextStyle.caption.font)
                    .foregroundStyle(KWColor.Text.muted)
                    .lineLimit(1)
                if let alreadySplit = viewModel.alreadySplit {
                    Text(alreadySplit)
                        .font(KWTextStyle.caption.font)
                        .foregroundStyle(KWColor.Text.secondary)
                        .monospacedDigit()
                }
            }
            ScrollView {
                shares
                    .padding(.bottom, KWSpacing.md)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.immediately)
            if let error = viewModel.errorMessage {
                Text(error).font(KWTextStyle.caption.font).foregroundStyle(KWColor.State.negative)
            }
            Button {
                KWKeyboard.dismiss()
                Task {
                    if await viewModel.save() {
                        onDone()
                    }
                }
            } label: {
                Text("Split", bundle: #bundle)
            }
            .buttonStyle(.kw())
            .disabled(!viewModel.canSave)
        }
        .padding(.horizontal, KWLayout.gutter)
        .padding(.top, KWSpacing.xl)
        .padding(.bottom, KWSpacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(KWColor.Surface.bg)
        .foregroundStyle(KWColor.Text.primary)
        .task { await viewModel.load() }
    }

    private var shares: some View {
        VStack(alignment: .leading, spacing: KWSpacing.md) {
            KWGroupedCard {
                ForEach(viewModel.shares) { share in
                    shareRow(share)
                }
            }
            HStack {
                Button { viewModel.addPerson() } label: {
                    Text("Add person", bundle: #bundle)
                }
                .buttonStyle(.kw(.surface, size: .small))
                Button { viewModel.splitEqually() } label: {
                    Text("Split equally", bundle: #bundle)
                }
                .buttonStyle(.kw(.surface, size: .small))
            }
            Text(viewModel.yourShare)
                .font(KWTextStyle.caption.font)
                .foregroundStyle(KWColor.Text.secondary)
                .monospacedDigit()
            Text("Each person gets a debt that owes you their share. Your movement doesn't change.", bundle: #bundle)
                .font(KWTextStyle.captionSm.font.weight(.regular))
                .foregroundStyle(KWColor.Text.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func shareRow(_ share: SplitBillViewModel.Share) -> some View {
        HStack(spacing: KWSpacing.sm) {
            TextField(
                String(localized: "Name", bundle: #bundle),
                text: Binding(get: { share.person }, set: { viewModel.setPerson($0, for: share.id) }),
            )
            .font(KWTextStyle.body.font)
            HStack(spacing: 2) {
                Text(viewModel.symbol.trimmingCharacters(in: .whitespaces))
                    .foregroundStyle(KWColor.Text.muted)
                    .accessibilityHidden(true)
                TextField(
                    String(localized: "Amount", bundle: #bundle),
                    text: Binding(get: { share.amountText }, set: { viewModel.setAmount($0, for: share.id) }),
                )
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
            }
            .font(.kw(15, weight: 600))
            .frame(minHeight: 40)
            .kwInputField()
            .frame(maxWidth: 130)
            if viewModel.shares.count > 1 {
                Button { viewModel.remove(share.id) } label: {
                    KWIconView(.close, size: 16).foregroundStyle(KWColor.Text.muted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Remove", bundle: #bundle))
            }
        }
        .padding(.vertical, KWSpacing.xs)
    }
}
