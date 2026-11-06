import DesignSystem
import Domain
import SharedPresentation
import SwiftUI

/// Settings › Categories: one list per kind where every row opens the editor. "Reorder" swaps the
/// chevrons for up and down arrows, and "Restore default categories" sits at the end, behind a
/// confirmation, like the "Reset to default" banking apps put under a customizable list.
public struct CategoriesView: View {
    @Bindable private var viewModel: CategoriesViewModel
    private let onBack: () -> Void
    @State private var isConfirmingRestore = false

    public init(viewModel: CategoriesViewModel, onBack: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onBack = onBack
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KWSpacing.md) {
                header
                list
                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(KWTextStyle.caption.font)
                        .foregroundStyle(KWColor.State.negative)
                }
                restore
            }
            .padding(.horizontal, KWLayout.gutter)
            .padding(.top, KWLayout.safeTop)
            .padding(.bottom, KWSpacing.xxl)
        }
        .scrollIndicators(.hidden)
        .ignoresSafeArea(edges: .top)
        .background(KWColor.Surface.bg)
        .foregroundStyle(KWColor.Text.primary)
        .toolbar(.hidden, for: .navigationBar)
        .task { await viewModel.load() }
        .sheet(item: $viewModel.editor) { editor in
            editorSheet(editor)
                .presentationDetents([.large])
                .presentationBackground(KWColor.Surface.bg)
        }
        .confirmationDialog(
            String(localized: "Restore default categories?", bundle: #bundle),
            isPresented: $isConfirmingRestore,
            titleVisibility: .visible,
        ) {
            Button(role: .destructive) {
                Task { await viewModel.restore() }
            } label: {
                Text("Restore", bundle: #bundle)
            }
        } message: {
            Text("Deleted defaults come back and edits to them are undone. Your own categories and movements stay.", bundle: #bundle)
        }
    }

    /// The title with Reorder, the expense/income switch and, unless reordering, "New category".
    @ViewBuilder
    private var header: some View {
        HStack {
            KWNavigationHeader(String(localized: "Categories", bundle: #bundle), style: .large, onBack: onBack)
            Button { viewModel.isReordering.toggle() } label: {
                Text(viewModel.isReordering ? String(localized: "Done", bundle: #bundle) : String(
                    localized: "Reorder",
                    bundle: #bundle,
                ))
            }
            .buttonStyle(.kw(.secondary, size: .small))
            .fixedSize()
        }
        KWSegmentedControl(
            [
                (TransactionKind.expense, String(localized: "Expenses", bundle: #bundle)),
                (TransactionKind.income, String(localized: "Income", bundle: #bundle)),
            ],
            selection: $viewModel.kind,
        )
        if !viewModel.isReordering {
            Button(action: viewModel.startNew) {
                Label {
                    Text("New category", bundle: #bundle)
                } icon: {
                    KWIconView(.plus, size: 18)
                }
            }
            .buttonStyle(.kw(.secondary, size: .row))
        }
    }

    private func editorSheet(_ editor: CategoryEditorViewModel) -> some View {
        CategoryEditorView(
            viewModel: editor,
            onSaved: { _ in Task { await viewModel.editorFinished() } },
            onDeleted: { Task { await viewModel.editorFinished() } },
            onClose: { viewModel.editor = nil },
        )
    }

    private var list: some View {
        KWGroupedCard {
            ForEach(viewModel.visible) { category in
                if viewModel.isReordering {
                    reorderRow(category)
                } else {
                    Button { viewModel.edit(category) } label: {
                        row(category) {
                            KWIconView(.chevronRight, size: 16)
                                .foregroundStyle(KWColor.Text.muted)
                        }
                        .accessibilityElement(children: .combine)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(.isButton)
                }
            }
        }
    }

    private func reorderRow(_ category: TransactionCategory) -> some View {
        row(category) {
            if !category.isFallback {
                HStack(spacing: KWSpacing.xs) {
                    arrow(.arrowUp, category, by: -1, label: String(localized: "Move up", bundle: #bundle))
                    arrow(.arrowDown, category, by: 1, label: String(localized: "Move down", bundle: #bundle))
                }
            }
        }
    }

    private func arrow(_ icon: KWIcon, _ category: TransactionCategory, by offset: Int, label: String) -> some View {
        let isEnabled = viewModel.canMove(category, by: offset)
        return Button { Task { await viewModel.move(category, by: offset) } } label: {
            KWIconView(icon, size: 16)
                .foregroundStyle(isEnabled ? KWColor.Text.primary : KWColor.Text.faint)
                .frame(width: 34, height: 34)
                .background(KWColor.Surface.surface2, in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(label)
    }

    private func row(_ category: TransactionCategory, @ViewBuilder trailing: () -> some View) -> some View {
        let color = CategoryDisplay.color(for: category)
        return HStack(spacing: KWSpacing.sm) {
            CategorySymbol(category, size: 20)
                .foregroundStyle(color)
                .frame(width: 38, height: 38)
                .background(color.opacity(0.15), in: Circle())
            Text(CategoryDisplay.name(of: category))
                .font(KWTextStyle.body.font)
                .lineLimit(1)
            Spacer(minLength: KWSpacing.xs)
            trailing()
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private var restore: some View {
        VStack(alignment: .leading, spacing: KWSpacing.xs) {
            Text(
                "Deleting a category moves its movements to “\(viewModel.fallbackName)”, which stays so they always have a place.",
                bundle: #bundle,
            )
            .font(KWTextStyle.caption.font)
            .foregroundStyle(KWColor.Text.muted)
            .fixedSize(horizontal: false, vertical: true)
            Button { isConfirmingRestore = true } label: {
                Text("Restore default categories", bundle: #bundle)
            }
            .buttonStyle(.kw(.surface, size: .row))
        }
        .padding(.top, KWSpacing.xs)
    }
}
