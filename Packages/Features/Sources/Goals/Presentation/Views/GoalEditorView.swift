import Core
import DesignSystem
import Domain
import SharedPresentation
import SwiftUI

/// The sheet to create or edit a goal: a live preview, the name, the target and its currency, an
/// optional target month, then the same color and icon grids categories use.
struct GoalEditorView: View {
    @Bindable var viewModel: GoalEditorViewModel
    let onDone: () -> Void
    let onClose: () -> Void
    @State private var isConfirmingDelete = false
    @State private var isPickingMonth = false
    @FocusState private var isNameFocused: Bool
    @FocusState private var isTargetFocused: Bool

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
                viewModel.isCreating ? Text("Create goal", bundle: #bundle) : Text("Save", bundle: #bundle)
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
        .onAppear { isNameFocused = viewModel.isCreating }
        .onChange(of: isTargetFocused) { _, isFocused in
            if !isFocused {
                viewModel.formatTarget()
            }
        }
        .confirmationDialog(
            String(localized: "Delete this goal?", bundle: #bundle),
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
            Text("What you've set aside is only tracked here; your accounts don't change.", bundle: #bundle)
        }
    }

    private var title: String {
        viewModel.isCreating ? String(localized: "New goal", bundle: #bundle) : String(localized: "Edit goal", bundle: #bundle)
    }

    private var tint: Color {
        viewModel.color.flatMap(KWColor.categoryPalette(key:)) ?? KWColor.Brand.accent
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
            KWGroupedCard {
                KWAmountFieldRow(
                    String(localized: "Target", bundle: #bundle),
                    symbol: CurrencyFormatter.symbol(for: viewModel.currency),
                    text: $viewModel.targetText,
                )
                .focused($isTargetFocused)
                if viewModel.showsCurrencyPicker {
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
                targetMonth
            }
            KWSectionHeader(String(localized: "Color", bundle: #bundle))
            CategoryColorPicker(selection: $viewModel.color)
            KWSectionHeader(String(localized: "Icon", bundle: #bundle))
            CategorySymbolPicker(selection: $viewModel.icon)
            if viewModel.canDelete {
                Button { isConfirmingDelete = true } label: {
                    Text("Delete goal", bundle: #bundle)
                }
                .buttonStyle(.kw(.destructive, size: .row))
                .padding(.top, KWSpacing.xs)
            }
        }
    }

    private var preview: some View {
        VStack(spacing: KWSpacing.xs) {
            SavingsGoalBadge(symbol: viewModel.icon, tint: tint, size: 64)
            Text(viewModel.name.isEmpty ? String(localized: "Goal name", bundle: #bundle) : viewModel.name)
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

    /// "Target date › December 2026": tapping it opens a month and a year wheel, with "No date"
    /// to take the deadline away.
    @ViewBuilder
    private var targetMonth: some View {
        Button {
            KWKeyboard.dismiss()
            withAnimation(.snappy) {
                if !viewModel.hasTargetMonth {
                    viewModel.hasTargetMonth = true
                    isPickingMonth = true
                } else {
                    isPickingMonth.toggle()
                }
            }
        } label: {
            KWValueRow(
                String(localized: "Target date", bundle: #bundle),
                value: "\(viewModel.targetMonthTitle) ›",
                style: viewModel.hasTargetMonth ? .detail : .placeholder,
                verticalPadding: 14,
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        if isPickingMonth, viewModel.hasTargetMonth {
            HStack(spacing: 0) {
                Picker(selection: $viewModel.month) {
                    ForEach(viewModel.monthOptions, id: \.value) { option in
                        Text(option.title).tag(option.value)
                    }
                } label: {
                    EmptyView()
                }
                Picker(selection: $viewModel.year) {
                    ForEach(viewModel.yearOptions, id: \.self) { year in
                        Text(verbatim: "\(year)").tag(year)
                    }
                } label: {
                    EmptyView()
                }
            }
            .pickerStyle(.wheel)
            .frame(height: 150)
            Button {
                withAnimation(.snappy) {
                    viewModel.hasTargetMonth = false
                    isPickingMonth = false
                }
            } label: {
                Text("No date", bundle: #bundle)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.kw(.link, size: .text))
        }
    }
}
