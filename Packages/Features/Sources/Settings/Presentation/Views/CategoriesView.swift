import DesignSystem
import Domain
import SharedPresentation
import SwiftUI

/// Settings › Categories. The person's own categories come first, since those are the ones to
/// manage; the defaults follow for reference.
public struct CategoriesView: View {
    @Bindable private var viewModel: CategoriesViewModel
    private let onBack: () -> Void

    public init(viewModel: CategoriesViewModel, onBack: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onBack = onBack
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KWSpacing.md) {
                KWNavigationHeader(String(localized: "Categories", bundle: #bundle), style: .large, onBack: onBack)
                KWSegmentedControl(
                    [
                        (TransactionKind.expense, String(localized: "Expenses", bundle: #bundle)),
                        (TransactionKind.income, String(localized: "Income", bundle: #bundle)),
                    ],
                    selection: $viewModel.kind,
                )
                Button(action: viewModel.startNew) {
                    Label {
                        Text("New category", bundle: #bundle)
                    } icon: {
                        KWIconView(.plus, size: 18)
                    }
                }
                .buttonStyle(.kw(.secondary, size: .row))
                yours
                included
                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(KWTextStyle.caption.font)
                        .foregroundStyle(KWColor.State.negative)
                }
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
            CategoryEditorView(
                viewModel: editor,
                onSaved: { _ in Task { await viewModel.editorFinished() } },
                onDeleted: { Task { await viewModel.editorFinished() } },
                onClose: { viewModel.editor = nil },
            )
            .presentationDetents([.large])
            .presentationBackground(KWColor.Surface.bg)
        }
    }

    private var yours: some View {
        SettingsSection(title: String(localized: "Yours", bundle: #bundle)) {
            if viewModel.custom.isEmpty {
                Text("Create categories for what you track, with your own name, icon and color.", bundle: #bundle)
                    .font(KWTextStyle.caption.font)
                    .foregroundStyle(KWColor.Text.muted)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                KWGroupedCard {
                    ForEach(viewModel.custom) { category in
                        Button { viewModel.edit(category) } label: {
                            row(category, isEditable: true)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var included: some View {
        SettingsSection(title: String(localized: "Included", bundle: #bundle)) {
            KWGroupedCard {
                ForEach(viewModel.defaults) { category in
                    row(category, isEditable: false)
                }
            }
        }
    }

    private func row(_ category: TransactionCategory, isEditable: Bool) -> some View {
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
            if isEditable {
                KWIconView(.chevronRight, size: 16)
                    .foregroundStyle(KWColor.Text.muted)
            }
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isEditable ? .isButton : [])
    }
}
