import Core
import DesignSystem
import Domain
import RecurringDomain
import SharedPresentation
import SwiftUI

/// Creates or edits a recurring rule: what it is, how much, what pays, how often and from when.
/// Editing also shows its next dates and what it recorded, with "Pause" and "Delete" at the end.
public struct RecurringRuleEditorView: View {
    @Bindable private var viewModel: RecurringRuleEditorViewModel
    private let onBack: () -> Void
    private let onDone: () -> Void
    private let onOpenTransaction: (UUID) -> Void
    @State private var choice: Choice?
    @State private var isConfirmingDelete = false

    private enum Choice: String, Identifiable {
        case method
        case destination
        case category

        var id: String { rawValue }
    }

    /// `onDone` runs after saving or deleting; `onOpenTransaction` opens a movement the rule recorded.
    public init(
        viewModel: RecurringRuleEditorViewModel,
        onBack: @escaping () -> Void,
        onDone: @escaping () -> Void,
        onOpenTransaction: @escaping (UUID) -> Void,
    ) {
        self.viewModel = viewModel
        self.onBack = onBack
        self.onDone = onDone
        self.onOpenTransaction = onOpenTransaction
    }

    public var body: some View {
        KWFormScreen {
            VStack(alignment: .leading, spacing: KWSpacing.md) {
                KWNavigationHeader(viewModel.title, style: .large, onBack: onBack)
                if viewModel.overview != nil {
                    form
                }
            }
        } footer: {
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
        .toolbar(.hidden, for: .navigationBar)
        .task { await viewModel.load() }
        .sheet(item: $choice) { choice in
            choiceSheet(choice)
                .presentationDetents([.medium, .large])
                .presentationBackground(KWColor.Surface.bg)
        }
        .confirmationDialog(
            String(localized: "Delete this recurring movement?", bundle: #bundle),
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
            Text("Its drafts waiting for confirmation are deleted too. Movements already confirmed stay.", bundle: #bundle)
        }
    }

    @ViewBuilder
    private var form: some View {
        KWSegmentedControl(viewModel.kindOptions, selection: $viewModel.kind)
        KWGroupedCard {
            KWTextFieldRow(
                String(localized: "Name", bundle: #bundle),
                placeholder: String(localized: "Rent, Netflix…", bundle: #bundle),
                text: $viewModel.name,
            )
            KWAmountFieldRow(
                String(localized: "Amount", bundle: #bundle),
                symbol: CurrencyFormatter.symbol(for: viewModel.currency),
                text: $viewModel.amountText,
            )
            if viewModel.currencyOptions.count > 1 {
                menuRow(String(localized: "Currency", bundle: #bundle), value: viewModel.currency) {
                    ForEach(viewModel.currencyOptions, id: \.self) { code in
                        Button(code) { viewModel.currency = code }
                    }
                }
            }
        }
        KWGroupedCard {
            pickerRow(methodLabel, value: viewModel.methodTitle, choice: .method)
            if viewModel.kind == .transfer {
                pickerRow(String(localized: "To", bundle: #bundle), value: viewModel.destinationTitle, choice: .destination)
            } else {
                pickerRow(
                    String(localized: "Category", bundle: #bundle),
                    value: viewModel.category.map(CategoryDisplay.name(of:)),
                    choice: .category,
                )
            }
        }
        schedule
        options
        KWGroupedCard {
            KWTextFieldRow(
                String(localized: "Note", bundle: #bundle),
                placeholder: String(localized: "Optional", bundle: #bundle),
                text: $viewModel.note,
            )
        }
        RecurringRuleDetail(viewModel: viewModel, onOpenTransaction: onOpenTransaction)
        if viewModel.isEditing {
            manage
        }
    }

    private var schedule: some View {
        KWGroupedCard {
            menuRow(String(localized: "Repeats", bundle: #bundle), value: viewModel.repeatsTitle) {
                Picker(selection: $viewModel.frequency) {
                    ForEach(viewModel.frequencyOptions, id: \.value) { option in
                        Text(option.title).tag(option.value)
                    }
                } label: {
                    EmptyView()
                }
            }
            Stepper(value: $viewModel.interval, in: viewModel.intervalRange) {
                HStack(spacing: KWSpacing.xxs) {
                    Text("Every", bundle: #bundle).font(KWTextStyle.body.font).foregroundStyle(KWColor.Text.secondary)
                    Text(verbatim: "\(viewModel.interval)").font(.kw(15, weight: 600))
                }
            }
            .padding(.vertical, KWSpacing.xs)
            DatePicker(selection: $viewModel.startDate, displayedComponents: [.date]) {
                Text("Starts", bundle: #bundle).font(KWTextStyle.body.font).foregroundStyle(KWColor.Text.secondary)
            }
            .padding(.vertical, KWSpacing.xs)
            Toggle(isOn: $viewModel.hasEndDate.animation(.snappy)) {
                Text("Ends", bundle: #bundle).font(KWTextStyle.body.font)
            }
            .toggleStyle(.kw)
            .padding(.vertical, 14)
            if viewModel.hasEndDate {
                DatePicker(selection: $viewModel.endDate, in: viewModel.startDate..., displayedComponents: [.date]) {
                    Text("Last day", bundle: #bundle).font(KWTextStyle.body.font).foregroundStyle(KWColor.Text.secondary)
                }
                .padding(.vertical, KWSpacing.xs)
            }
        }
    }
}

extension RecurringRuleEditorView {
    private var options: some View {
        VStack(alignment: .leading, spacing: KWSpacing.xs) {
            KWGroupedCard {
                if viewModel.showsSubscriptionToggle {
                    Toggle(isOn: $viewModel.isSubscription) {
                        Text("Subscription", bundle: #bundle).font(KWTextStyle.body.font)
                    }
                    .toggleStyle(.kw)
                    .padding(.vertical, 14)
                }
                Toggle(isOn: $viewModel.autoConfirm) {
                    Text("Record automatically", bundle: #bundle).font(KWTextStyle.body.font)
                }
                .toggleStyle(.kw)
                .padding(.vertical, 14)
            }
            Text("Off: it waits as a draft for you to confirm.", bundle: #bundle)
                .font(KWTextStyle.captionSm.font.weight(.regular))
                .foregroundStyle(KWColor.Text.muted)
        }
    }

    private var manage: some View {
        VStack(spacing: KWSpacing.xs) {
            Button {
                Task { await viewModel.togglePaused() }
            } label: {
                viewModel.isPaused ? Text("Resume", bundle: #bundle) : Text("Pause", bundle: #bundle)
            }
            .buttonStyle(.kw(.surface, size: .row))
            Button { isConfirmingDelete = true } label: {
                Text("Delete", bundle: #bundle)
            }
            .buttonStyle(.kw(.destructive, size: .row))
        }
    }

    // MARK: Rows

    private func pickerRow(_ label: String, value: String?, choice: Choice) -> some View {
        Button { self.choice = choice } label: {
            KWValueRow(
                label,
                value: "\(value ?? String(localized: "Choose", bundle: #bundle)) ›",
                style: value == nil ? .placeholder : .detail,
                verticalPadding: 14,
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func menuRow(_ label: String, value: String, @ViewBuilder content: () -> some View) -> some View {
        Menu {
            content()
        } label: {
            KWValueRow(label, value: "\(value) ›", verticalPadding: 14)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Pickers

    private var methodLabel: String {
        viewModel.kind == .transfer ? String(localized: "From", bundle: #bundle) : String(localized: "Payment method", bundle: #bundle)
    }

    @ViewBuilder
    private func choiceSheet(_ choice: Choice) -> some View {
        switch choice {
        case .method:
            RecurringChoiceSheet(
                title: methodLabel,
                options: viewModel.methodOptions,
                isSelected: { $0.method == viewModel.method },
                row: { option in
                    RecurringChoiceRow(title: option.title, subtitle: option.subtitle) { MethodThumbnail(thumbnail: option.thumbnail) }
                },
                onSelect: { option in
                    viewModel.selectMethod(option.method)
                    self.choice = nil
                },
            )
        case .destination:
            RecurringChoiceSheet(
                title: String(localized: "To", bundle: #bundle),
                options: viewModel.destinationOptions,
                isSelected: { $0.id == viewModel.destinationAccountID },
                row: { account in
                    RecurringChoiceRow(title: CardDisplay.name(of: account), subtitle: account.currencies.formatted(.list(type: .and))) {
                        MethodThumbnail(thumbnail: account.kind == .cash ? .cash : .transfer)
                    }
                },
                onSelect: { account in
                    viewModel.destinationAccountID = account.id
                    self.choice = nil
                },
            )
        case .category:
            RecurringChoiceSheet(
                title: String(localized: "Category", bundle: #bundle),
                options: viewModel.categoryOptions,
                isSelected: { $0.id == viewModel.category?.id },
                row: { category in
                    RecurringChoiceRow(title: CategoryDisplay.name(of: category), subtitle: nil) {
                        CategorySymbol(category, size: 20)
                            .foregroundStyle(CategoryDisplay.color(for: category))
                            .frame(width: 40, height: 40)
                            .background(KWColor.Surface.surface2, in: Circle())
                    }
                },
                onSelect: { category in
                    viewModel.selectCategory(category.id)
                    self.choice = nil
                },
            )
        }
    }
}

#Preview {
    RecurringPreview.editor()
}
