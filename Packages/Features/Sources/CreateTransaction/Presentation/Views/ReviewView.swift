import DesignSystem
import SharedPresentation
import SwiftUI

/// Step 4 · Review: description, date, real debit, planned, shared and note.
public struct ReviewView: View {
    @Bindable private var viewModel: CreateTransactionViewModel
    private let onBack: () -> Void
    @State private var isPickingDate = false

    public init(viewModel: CreateTransactionViewModel, onBack: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onBack = onBack
    }

    public var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                form
                    .padding(.horizontal, KWLayout.gutter)
                    .padding(.top, KWLayout.safeTop)
                    .padding(.bottom, KWSpacing.md)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            Button(viewModel.saveTitle) {
                KWKeyboard.dismiss()
                Task { await viewModel.save() }
            }
            .buttonStyle(.kw())
            .disabled(!viewModel.canSave)
            .padding(.horizontal, KWLayout.gutter)
            .padding(.top, KWSpacing.sm)
            .padding(.bottom, 34)
        }
        .ignoresSafeArea(.container, edges: [.top, .bottom])
        .onAppear { viewModel.prefillDescription() }
        .background(KWColor.Surface.bg)
        .foregroundStyle(KWColor.Text.primary)
        .sheet(isPresented: $isPickingDate) {
            DatePicker(selection: $viewModel.date, displayedComponents: [.date]) {
                Text("Date", bundle: #bundle)
            }
            .datePickerStyle(.graphical)
            .padding(KWLayout.gutter)
            .presentationDetents([.medium])
            .presentationBackground(KWColor.Surface.surface)
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 14) {
            KWFlowHeader(.back, progress: (4, 4), action: onBack)
            summary
            labeledField(
                String(localized: "Description", bundle: #bundle),
                text: $viewModel.description,
                placeholder: viewModel.descriptionPlaceholder,
                font: .kw(17, weight: 600),
            )
            KWGroupedCard {
                details
            }
            labeledField(
                String(localized: "Note", bundle: #bundle),
                text: $viewModel.note,
                placeholder: String(localized: "Add a detail", bundle: #bundle),
                font: KWTextStyle.body.font,
            )
            if let error = viewModel.errorMessage {
                Text(error).font(KWTextStyle.caption.font).foregroundStyle(KWColor.State.negative)
            }
        }
    }

    private var summary: some View {
        VStack(spacing: 6) {
            KWIconView(viewModel.kind == .transfer ? .transfer : CategoryDisplay.icon(for: viewModel.categoryID), size: 26)
                .frame(width: 56, height: 56)
                .background(KWColor.Surface.surface2, in: Circle())
            Text(viewModel.reviewAmount)
                .font(.kw(40, weight: 800, relativeTo: .largeTitle))
                .tracking(-1.2)
                .monospacedDigit()
            Text(viewModel.reviewSubtitle)
                .font(KWTextStyle.label.font.weight(.regular))
                .foregroundStyle(KWColor.Text.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, KWSpacing.xs)
    }

    @ViewBuilder
    private var details: some View {
        if viewModel.kind == .transfer {
            KWValueRow(String(localized: "Leaves from", bundle: #bundle), value: viewModel.accountLabel(viewModel.sourceAccount))
            KWValueRow(String(localized: "Goes into", bundle: #bundle), value: viewModel.accountLabel(viewModel.destinationAccount))
        } else {
            KWValueRow(sourceRowTitle, value: viewModel.accountLabel(viewModel.sourceAccount))
        }
        Button { isPickingDate = true } label: {
            KWValueRow(String(localized: "Date", bundle: #bundle), value: "\(viewModel.dayLabel(viewModel.date)) ›")
        }
        .buttonStyle(.plain)
        if viewModel.showsDebitedField {
            debitedRow
        }
        Toggle(isOn: $viewModel.isPlanned) {
            hint(viewModel.plannedLabel, viewModel.plannedHint)
        }
        .toggleStyle(.kw(tint: KWColor.State.pending))
        .padding(.vertical, 11)
        if viewModel.kind == .expense {
            Toggle(isOn: $viewModel.isShared) {
                hint(String(localized: "Shared", bundle: #bundle), String(localized: "Others owe you a share", bundle: #bundle))
            }
            .toggleStyle(.kw)
            .padding(.vertical, 11)
        }
    }

    private var sourceRowTitle: String {
        viewModel.kind == .income
            ? String(localized: "Goes into", bundle: #bundle)
            : String(localized: "Charged to", bundle: #bundle)
    }

    private var debitedTitle: String {
        let principal = viewModel.context?.currencies.principal ?? "USD"
        return String(localized: "\(principal) charged by the bank", bundle: #bundle)
    }

    private var debitedRow: some View {
        HStack(spacing: KWSpacing.sm) {
            hint(debitedTitle, String(localized: "Optional · if a different rate was used", bundle: #bundle))
            Spacer()
            TextField(viewModel.suggestedDebit, text: $viewModel.debitedText)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(.kw(15, weight: 600))
                .monospacedDigit()
                .padding(.vertical, KWSpacing.xs)
                .padding(.horizontal, 10)
                .frame(width: 84)
                .background(KWColor.Surface.surface2, in: RoundedRectangle(cornerRadius: 10))
        }
        .padding(.vertical, 11)
    }

    private func hint(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(KWTextStyle.body.font).foregroundStyle(KWColor.Text.secondary)
            Text(subtitle).font(KWTextStyle.captionSm.font).foregroundStyle(KWColor.Text.muted)
        }
    }

    private func labeledField(_ label: String, text: Binding<String>, placeholder: String, font: Font) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(KWTextStyle.caption.font.weight(.regular)).foregroundStyle(KWColor.Text.muted)
            TextField(placeholder, text: text)
                .font(font)
        }
        .padding(.horizontal, KWSpacing.md)
        .padding(.vertical, KWSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(KWColor.Surface.surface, in: RoundedRectangle(cornerRadius: KWRadius.surface))
    }
}
