import Core
import DesignSystem
import Domain
import SwiftUI

/// The sheet to create or edit a category: a live preview, the name, a color row and a grid of
/// icons, the pattern finance apps use for custom categories.
public struct CategoryEditorView: View {
    @Bindable private var viewModel: CategoryEditorViewModel
    private let onSaved: (TransactionCategory) -> Void
    private let onDeleted: () -> Void
    private let onClose: () -> Void
    @State private var isConfirmingDelete = false
    @FocusState private var isNameFocused: Bool
    @FocusState private var isBudgetFocused: Bool

    public init(
        viewModel: CategoryEditorViewModel,
        onSaved: @escaping (TransactionCategory) -> Void,
        onDeleted: @escaping () -> Void = {},
        onClose: @escaping () -> Void,
    ) {
        self.viewModel = viewModel
        self.onSaved = onSaved
        self.onDeleted = onDeleted
        self.onClose = onClose
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: KWSpacing.md) {
            KWFlowHeader(.close, action: onClose)
            Text(title).kwTextStyle(.titleSm).accessibilityAddTraits(.isHeader)
            ScrollView {
                form.padding(.bottom, KWSpacing.md)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.immediately)
            Button {
                Task {
                    if let saved = await viewModel.save() {
                        onSaved(saved)
                    }
                }
            } label: {
                Text(viewModel.isCreating ? String(localized: "Create category", bundle: #bundle) : String(
                    localized: "Save",
                    bundle: #bundle,
                ))
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
        .onAppear { isNameFocused = viewModel.isCreating && viewModel.name.isEmpty }
        .onChange(of: isBudgetFocused) { _, isFocused in
            if !isFocused {
                viewModel.formatBudget()
            }
        }
        .confirmationDialog(
            String(localized: "Delete this category?", bundle: #bundle),
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible,
        ) {
            Button(role: .destructive) {
                Task {
                    if await viewModel.delete() {
                        onDeleted()
                    }
                }
            } label: {
                Text("Delete", bundle: #bundle)
            }
        } message: {
            Text("Its movements move to “\(viewModel.fallbackName)”.", bundle: #bundle)
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: KWSpacing.md) {
            preview
            nameField
            if let error = viewModel.errorMessage {
                Text(error)
                    .font(KWTextStyle.caption.font)
                    .foregroundStyle(KWColor.State.negative)
            }
            if viewModel.showsBudget {
                budget
            }
            KWSectionHeader(String(localized: "Color", bundle: #bundle))
            CategoryColorPicker(selection: $viewModel.color)
            KWSectionHeader(String(localized: "Icon", bundle: #bundle))
            CategorySymbolPicker(selection: $viewModel.icon)
            if viewModel.isFallback {
                Text("Movements from deleted categories land here, so this one can be renamed but not deleted.", bundle: #bundle)
                    .font(KWTextStyle.caption.font)
                    .foregroundStyle(KWColor.Text.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if viewModel.canDelete {
                Button { isConfirmingDelete = true } label: {
                    Text("Delete category", bundle: #bundle)
                }
                .buttonStyle(.kw(.destructive, size: .row))
                .padding(.top, KWSpacing.xs)
            }
        }
    }

    private var title: String {
        viewModel.isCreating ? String(localized: "New category", bundle: #bundle) : String(localized: "Edit category", bundle: #bundle)
    }

    private var tint: Color {
        CategoryDisplay.color(for: viewModel.preview)
    }

    private var preview: some View {
        VStack(spacing: KWSpacing.xs) {
            CategorySymbol(symbol: viewModel.icon, size: 30)
                .foregroundStyle(tint)
                .frame(width: 64, height: 64)
                .background(tint.opacity(0.15), in: Circle())
            Text(viewModel.name.isEmpty ? String(localized: "Category name", bundle: #bundle) : viewModel.name)
                .font(KWTextStyle.heading.font)
                .foregroundStyle(viewModel.name.isEmpty ? KWColor.Text.muted : KWColor.Text.primary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, KWSpacing.xs)
        .accessibilityHidden(true)
    }

    private var nameField: some View {
        TextField(
            String(localized: "Name", bundle: #bundle),
            text: Binding(get: { viewModel.name }, set: viewModel.setName),
        )
        .font(KWTextStyle.body.font)
        .focused($isNameFocused)
        .submitLabel(.done)
        .padding(.horizontal, 14)
        .frame(height: 48)
        .background(KWColor.Surface.surface, in: RoundedRectangle(cornerRadius: KWRadius.card))
    }

    private var budget: some View {
        VStack(alignment: .leading, spacing: KWSpacing.xs) {
            KWGroupedCard {
                KWAmountFieldRow(
                    String(localized: "Monthly budget", bundle: #bundle),
                    symbol: viewModel.principalCurrency.map(CurrencyFormatter.symbol(for:)),
                    placeholder: String(localized: "No limit", bundle: #bundle),
                    text: $viewModel.budgetText,
                )
                .focused($isBudgetFocused)
            }
            Text(viewModel.budgetFooter)
                .font(KWTextStyle.caption.font)
                .foregroundStyle(KWColor.Text.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
