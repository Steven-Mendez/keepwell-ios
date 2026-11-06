import DesignSystem
import Domain
import SharedPresentation
import SwiftUI

/// Settings › Rules: "“Uber” → Transport" rows that open the editor. "Reorder" swaps the chevrons
/// for up and down arrows, as in Categories, since the first rule that matches wins.
public struct RulesView: View {
    @Bindable private var viewModel: RulesViewModel
    private let onBack: () -> Void

    public init(viewModel: RulesViewModel, onBack: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onBack = onBack
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KWSpacing.md) {
                header
                if viewModel.rules.isEmpty {
                    empty
                } else {
                    list
                }
                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(KWTextStyle.caption.font)
                        .foregroundStyle(KWColor.State.negative)
                }
                Text(
                    "New movements take the category of the first rule that matches, unless you pick one. Past ones stay as they are.",
                    bundle: #bundle,
                )
                .font(KWTextStyle.caption.font)
                .foregroundStyle(KWColor.Text.muted)
                .fixedSize(horizontal: false, vertical: true)
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
            RuleEditorView(
                viewModel: editor,
                onDone: { Task { await viewModel.editorFinished() } },
                onClose: { viewModel.editor = nil },
            )
            .presentationDetents([.large])
            .presentationBackground(KWColor.Surface.bg)
        }
    }

    @ViewBuilder
    private var header: some View {
        HStack {
            KWNavigationHeader(String(localized: "Rules", bundle: #bundle), style: .large, onBack: onBack)
            if viewModel.rules.count > 1 {
                Button { viewModel.isReordering.toggle() } label: {
                    Text(viewModel.isReordering ? String(localized: "Done", bundle: #bundle) : String(
                        localized: "Reorder",
                        bundle: #bundle,
                    ))
                }
                .buttonStyle(.kw(.secondary, size: .small))
                .fixedSize()
            }
        }
        if !viewModel.isReordering {
            Button(action: viewModel.startNew) {
                Label {
                    Text("New rule", bundle: #bundle)
                } icon: {
                    KWIconView(.plus, size: 18)
                }
            }
            .buttonStyle(.kw(.secondary, size: .row))
        }
    }

    private var empty: some View {
        KWEmptyState(
            icon: .bolt,
            title: String(localized: "No rules yet", bundle: #bundle),
            message: String(
                localized: "Teach Keepwell that “Uber” is Transport, and new movements that say so get it on their own.",
                bundle: #bundle,
            ),
        )
        .padding(.top, KWSpacing.xl)
    }

    private var list: some View {
        KWGroupedCard {
            ForEach(viewModel.rules) { rule in
                if viewModel.isReordering {
                    row(rule) {
                        HStack(spacing: KWSpacing.xs) {
                            arrow(.arrowUp, rule, by: -1, label: String(localized: "Move up", bundle: #bundle))
                            arrow(.arrowDown, rule, by: 1, label: String(localized: "Move down", bundle: #bundle))
                        }
                    }
                } else {
                    Button { viewModel.edit(rule) } label: {
                        row(rule) {
                            KWIconView(.chevronRight, size: 16).foregroundStyle(KWColor.Text.muted)
                        }
                        .accessibilityElement(children: .combine)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(.isButton)
                }
            }
        }
    }

    private func arrow(_ icon: KWIcon, _ rule: CategorizationRule, by offset: Int, label: String) -> some View {
        let isEnabled = viewModel.canMove(rule, by: offset)
        return Button { Task { await viewModel.move(rule, by: offset) } } label: {
            KWIconView(icon, size: 16)
                .foregroundStyle(isEnabled ? KWColor.Text.primary : KWColor.Text.faint)
                .frame(width: 34, height: 34)
                .background(KWColor.Surface.surface2, in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(label)
    }

    private func row(_ rule: CategorizationRule, @ViewBuilder trailing: () -> some View) -> some View {
        let category = viewModel.category(of: rule)
        let color = category.map(CategoryDisplay.color(for:)) ?? KWColor.Text.muted
        return HStack(spacing: KWSpacing.sm) {
            CategorySymbol(category, size: 20)
                .foregroundStyle(color)
                .frame(width: 38, height: 38)
                .background(color.opacity(0.15), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text("“\(rule.match)” → \(viewModel.categoryName(of: rule))", bundle: #bundle)
                    .font(KWTextStyle.body.font)
                    .lineLimit(1)
                Text(viewModel.detail(of: rule))
                    .font(KWTextStyle.caption.font.weight(.regular))
                    .foregroundStyle(KWColor.Text.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: KWSpacing.xs)
            trailing()
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}
