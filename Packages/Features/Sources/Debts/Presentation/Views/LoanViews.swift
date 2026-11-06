import Core
import DebtsDomain
import DesignSystem
import Domain
import SharedPresentation
import SwiftUI

/// The sheet to create or edit a loan.
struct LoanEditorView: View {
    @Bindable var viewModel: LoanEditorViewModel
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
                viewModel.isCreating ? Text("Add loan", bundle: #bundle) : Text("Save", bundle: #bundle)
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
            String(localized: "Delete this loan?", bundle: #bundle),
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
            Text("The installments you already paid stay as movements.", bundle: #bundle)
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: KWSpacing.md) {
            KWGroupedCard {
                KWTextFieldRow(
                    String(localized: "Name", bundle: #bundle),
                    placeholder: String(localized: "Motorbike, mortgage…", bundle: #bundle),
                    text: $viewModel.name,
                )
                KWTextFieldRow(
                    String(localized: "Lender", bundle: #bundle),
                    placeholder: String(localized: "Optional", bundle: #bundle),
                    text: $viewModel.lender,
                )
            }
            amounts
            if let total = viewModel.totalLine {
                Text(total)
                    .font(KWTextStyle.captionSm.font.weight(.regular))
                    .foregroundStyle(KWColor.Text.muted)
                    .padding(.horizontal, KWSpacing.xxs)
            }
            KWSegmentedControl(viewModel.frequencyOptions, selection: $viewModel.frequency)
            KWGroupedCard {
                DatePicker(selection: $viewModel.firstDueDate, displayedComponents: [.date]) {
                    Text("First installment", bundle: #bundle).font(KWTextStyle.body.font).foregroundStyle(KWColor.Text.secondary)
                }
                .padding(.vertical, KWSpacing.xs)
            }
            if !viewModel.isCreating {
                Button { isConfirmingDelete = true } label: {
                    Text("Delete loan", bundle: #bundle)
                }
                .buttonStyle(.kw(.destructive, size: .row))
                .padding(.top, KWSpacing.xs)
            }
        }
    }

    private var amounts: some View {
        KWGroupedCard {
            KWAmountFieldRow(
                String(localized: "Amount borrowed", bundle: #bundle),
                symbol: CurrencyFormatter.symbol(for: viewModel.currency),
                text: $viewModel.borrowedText,
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
            KWAmountFieldRow(
                String(localized: "Installment", bundle: #bundle),
                symbol: CurrencyFormatter.symbol(for: viewModel.currency),
                text: $viewModel.installmentText,
            )
            KWTextFieldRow(
                String(localized: "Number of installments", bundle: #bundle),
                placeholder: "12",
                text: $viewModel.countText,
                digitLimit: 3,
                width: 90,
            )
        }
    }
}

/// A loan's detail: what is left, "Pay installment" with where it's paid from, and the schedule.
struct LoanDetailView: View {
    @Bindable var viewModel: LoanDetailViewModel
    let hidesBalances: Bool
    let onEdit: () -> Void
    let onClose: () -> Void
    /// The paid installment waiting for "Mark unpaid" to be confirmed.
    @State private var unpaying: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: KWSpacing.md) {
            KWFlowHeader(.close, action: onClose)
            HStack(alignment: .firstTextBaseline) {
                Text(viewModel.loan.name).kwTextStyle(.titleSm).accessibilityAddTraits(.isHeader)
                Spacer()
                Button(action: onEdit) {
                    Text("Edit", bundle: #bundle).font(KWTextStyle.label.font).foregroundStyle(KWColor.Brand.link)
                }
                .buttonStyle(.plain)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: KWSpacing.md) {
                    summary
                    if viewModel.progress.next != nil {
                        payment
                    }
                    KWSectionHeader(String(localized: "Schedule", bundle: #bundle))
                    KWGroupedCard {
                        ForEach(viewModel.progress.installments, id: \.number) { installment in
                            installmentRow(installment)
                        }
                    }
                    if viewModel.loan.paidCount > 0 {
                        Text("Touch and hold a paid installment to mark it unpaid.", bundle: #bundle)
                            .font(KWTextStyle.captionSm.font.weight(.regular))
                            .foregroundStyle(KWColor.Text.muted)
                    }
                }
                .padding(.bottom, KWSpacing.md)
            }
            .scrollIndicators(.hidden)
        }
        .padding(.horizontal, KWLayout.gutter)
        .padding(.top, KWSpacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(KWColor.Surface.bg)
        .foregroundStyle(KWColor.Text.primary)
        .task { await viewModel.load() }
        .confirmationDialog(
            unpaying.map(viewModel.unpayTitle) ?? "",
            isPresented: Binding(get: { unpaying != nil }, set: {
                if !$0 {
                    unpaying = nil
                }
            }),
            titleVisibility: .visible,
            presenting: unpaying,
        ) { number in
            Button(role: .destructive) {
                Task { await viewModel.markUnpaid(number) }
            } label: {
                Text("Mark unpaid", bundle: #bundle)
            }
        } message: { _ in
            Text("The expense it recorded is deleted, so balances go back to before you paid it.", bundle: #bundle)
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: KWSpacing.xs) {
            Text(viewModel.summary(hidden: hidesBalances))
                .font(.kw(15, weight: 600))
                .monospacedDigit()
            KWProgressBar(
                paidFraction(viewModel.progress),
                fill: viewModel.progress.isPaidOff ? KWColor.State.positive : KWColor.Brand.accent,
                height: 8,
            )
            Text(viewModel.borrowedLine(hidden: hidesBalances))
                .font(KWTextStyle.caption.font)
                .foregroundStyle(KWColor.Text.muted)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(KWColor.Surface.surface, in: RoundedRectangle(cornerRadius: KWRadius.surface, style: .continuous))
    }

    private var payment: some View {
        VStack(alignment: .leading, spacing: KWSpacing.xs) {
            KWGroupedCard {
                Menu {
                    ForEach(viewModel.methods, id: \.self) { option in
                        Button(option.title) { viewModel.method = option.source }
                    }
                } label: {
                    KWValueRow(String(localized: "Pay from", bundle: #bundle), value: "\(viewModel.methodTitle) ›", verticalPadding: 14)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Menu {
                    ForEach(viewModel.categories) { category in
                        Button(CategoryDisplay.name(of: category)) { viewModel.categoryID = category.id }
                    }
                } label: {
                    KWValueRow(String(localized: "Category", bundle: #bundle), value: "\(viewModel.categoryTitle) ›", verticalPadding: 14)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                DatePicker(selection: $viewModel.paymentDate, displayedComponents: [.date]) {
                    Text("Paid on", bundle: #bundle).font(KWTextStyle.body.font).foregroundStyle(KWColor.Text.secondary)
                }
                .padding(.vertical, KWSpacing.xs)
            }
            if let error = viewModel.errorMessage {
                Text(error).font(KWTextStyle.caption.font).foregroundStyle(KWColor.State.negative)
            }
            Button {
                Task { await viewModel.pay() }
            } label: {
                Text(viewModel.payTitle)
            }
            .buttonStyle(.kw())
            .disabled(!viewModel.canPay)
            Text("Records a confirmed expense from the account or card you pick.", bundle: #bundle)
                .font(KWTextStyle.captionSm.font.weight(.regular))
                .foregroundStyle(KWColor.Text.muted)
        }
    }

    private func installmentRow(_ installment: LoanInstallment) -> some View {
        HStack(spacing: KWSpacing.sm) {
            KWIconView(installment.isPaid ? .check : .clock, size: 18)
                .foregroundStyle(installment.isPaid ? KWColor.State.positive : KWColor.Text.muted)
                .frame(width: 24)
            Text(verbatim: "\(installment.number)/\(viewModel.loan.installmentCount)")
                .font(.kw(15, weight: 600))
                .monospacedDigit()
            Spacer(minLength: KWSpacing.xs)
            Text(viewModel.dueDay(installment))
                .font(KWTextStyle.caption.font)
                .foregroundStyle(KWColor.Text.secondary)
            Text(installment.isPaid ? String(localized: "Paid", bundle: #bundle) : String(localized: "Due", bundle: #bundle))
                .font(KWTextStyle.captionSm.font)
                .foregroundStyle(installment.isPaid ? KWColor.State.positive : KWColor.Text.muted)
                .frame(width: 56, alignment: .trailing)
        }
        .padding(.vertical, KWSpacing.xs)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .contextMenu {
            if installment.isPaid {
                Button(role: .destructive) { unpaying = installment.number } label: {
                    Label { Text("Mark unpaid", bundle: #bundle) } icon: { Image(systemName: "arrow.uturn.backward") }
                }
            }
        }
        .accessibilityActions {
            if installment.isPaid {
                Button { unpaying = installment.number } label: { Text("Mark unpaid", bundle: #bundle) }
            }
        }
    }
}
