import DesignSystem
import Domain
import SharedPresentation
import SwiftUI

/// The sheet to create or edit a rule: what the description or note contains, expense or income,
/// the category it gets and tags to add. An existing rule can be applied to past movements.
struct RuleEditorView: View {
    @Bindable var viewModel: RuleEditorViewModel
    let onDone: () -> Void
    let onClose: () -> Void
    @State private var isConfirmingDelete = false
    @FocusState private var isMatchFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: KWSpacing.md) {
            KWFlowHeader(.close, action: onClose)
            Text(title).kwTextStyle(.titleSm).accessibilityAddTraits(.isHeader)
            ScrollView {
                form.padding(.bottom, KWSpacing.md)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.immediately)
            Button {
                KWKeyboard.dismiss()
                Task {
                    if await viewModel.save() != nil {
                        onDone()
                    }
                }
            } label: {
                viewModel.isCreating ? Text("Create rule", bundle: #bundle) : Text("Save", bundle: #bundle)
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
        .onAppear { isMatchFocused = viewModel.isCreating }
        .confirmationDialog(
            String(localized: "Delete this rule?", bundle: #bundle),
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
        } message: {
            Text("Movements it already categorized stay as they are.", bundle: #bundle)
        }
        .confirmationDialog(
            viewModel.applyToPastTitle,
            isPresented: Binding(get: { viewModel.pastMatchCount != nil }, set: { isShown in
                if !isShown {
                    viewModel.pastMatchCount = nil
                }
            }),
            titleVisibility: .visible,
        ) {
            Button {
                Task { await viewModel.applyToPast() }
            } label: {
                Text("Apply", bundle: #bundle)
            }
        } message: {
            Text("Only movements without a category or in “Other” that match change.", bundle: #bundle)
        }
    }

    private var title: String {
        viewModel.isCreating ? String(localized: "New rule", bundle: #bundle) : String(localized: "Edit rule", bundle: #bundle)
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: KWSpacing.md) {
            KWSegmentedControl(
                [
                    (TransactionKind.expense, String(localized: "Expenses", bundle: #bundle)),
                    (TransactionKind.income, String(localized: "Income", bundle: #bundle)),
                ],
                selection: $viewModel.kind,
            )
            matchField
            KWGroupedCard { categoryMenu }
            VStack(alignment: .leading, spacing: KWSpacing.xxs) {
                KWSectionHeader(String(localized: "Tags to add", bundle: #bundle))
                KWGroupedCard {
                    TagEditor(tags: $viewModel.tags, usage: viewModel.tagUsage)
                }
            }
            if let error = viewModel.errorMessage {
                Text(error).font(KWTextStyle.caption.font).foregroundStyle(KWColor.State.negative)
            }
            if viewModel.canApplyToPast {
                applyToPast
            }
            if viewModel.canDelete {
                Button { isConfirmingDelete = true } label: {
                    Text("Delete rule", bundle: #bundle)
                }
                .buttonStyle(.kw(.destructive, size: .row))
            }
        }
    }

    private var matchField: some View {
        VStack(alignment: .leading, spacing: KWSpacing.xxs) {
            KWSectionHeader(String(localized: "If the description or note contains", bundle: #bundle))
            TextField(
                String(localized: "Text to look for", bundle: #bundle),
                text: Binding(get: { viewModel.match }, set: viewModel.setMatch),
                prompt: Text("Uber", bundle: #bundle).foregroundStyle(KWColor.Text.faint),
            )
            .font(KWTextStyle.body.font)
            .autocorrectionDisabled()
            .focused($isMatchFocused)
            .submitLabel(.done)
            .padding(.horizontal, 14)
            .frame(height: 48)
            .background(KWColor.Surface.surface, in: RoundedRectangle(cornerRadius: KWRadius.card))
            Text("Capitals and accents don't matter.", bundle: #bundle)
                .font(KWTextStyle.captionSm.font.weight(.regular))
                .foregroundStyle(KWColor.Text.muted)
        }
    }

    private var categoryMenu: some View {
        Menu {
            ForEach(viewModel.categories) { category in
                Button(CategoryDisplay.name(of: category)) { viewModel.categoryID = category.id }
            }
        } label: {
            KWValueRow(
                String(localized: "Category", bundle: #bundle),
                value: "\(viewModel.categoryTitle) ›",
                style: viewModel.categoryID == nil ? .placeholder : .detail,
                verticalPadding: 14,
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var applyToPast: some View {
        VStack(alignment: .leading, spacing: KWSpacing.xs) {
            Button {
                KWKeyboard.dismiss()
                Task { await viewModel.prepareApplyToPast() }
            } label: {
                Text("Apply to past movements", bundle: #bundle)
            }
            .buttonStyle(.kw(.surface, size: .row))
            if let message = viewModel.appliedMessage {
                Text(message).font(KWTextStyle.caption.font).foregroundStyle(KWColor.Text.secondary)
            }
        }
    }
}
