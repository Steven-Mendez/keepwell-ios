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
            KWSectionHeader(String(localized: "Color", bundle: #bundle))
            colors
            KWSectionHeader(String(localized: "Icon", bundle: #bundle))
            icons
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

    private var colors: some View {
        // Two rows of five, so every color and the selected one stay in view.
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: KWSpacing.xs), count: 5), spacing: KWSpacing.xs) {
            ForEach(CategoryDisplay.colorChoices, id: \.self) { key in
                let isSelected = key == viewModel.color
                Button { viewModel.color = key } label: {
                    Circle()
                        .fill(KWColor.categoryPalette(key: key) ?? KWColor.Text.faint)
                        .frame(width: 36, height: 36)
                        .padding(3)
                        .overlay(Circle().strokeBorder(isSelected ? Color.white : .clear, lineWidth: 2))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(CategoryDisplay.colorName(key))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }

    private var icons: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: KWSpacing.xs), count: 6), spacing: KWSpacing.xs) {
            ForEach(CategoryDisplay.symbolChoices, id: \.self) { symbol in
                let isSelected = symbol == viewModel.icon
                Button { viewModel.icon = symbol } label: {
                    CategorySymbol(symbol: symbol, size: 22)
                        .foregroundStyle(isSelected ? Color.black : KWColor.Text.primary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(isSelected ? Color.white : KWColor.Surface.surface, in: RoundedRectangle(cornerRadius: 12))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(verbatim: symbol))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }
}
