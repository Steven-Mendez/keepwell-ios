import DesignSystem
import Domain
import SharedPresentation
import SwiftUI

/// The last look before saving: a card with the amount and both ends of the movement (each one
/// tappable to change it), the details, and a slide to confirm so money never moves on a stray tap.
public struct ReviewView: View {
    @Bindable private var viewModel: CreateTransactionViewModel
    private let onBack: () -> Void
    @State private var isPickingDate = false
    @State private var isEditingNote = false
    /// Recreates the slider after a failed save, so it returns to the start.
    @State private var attempt = 0

    public init(viewModel: CreateTransactionViewModel, onBack: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onBack = onBack
    }

    public var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    summaryCard.padding(.top, 30)
                    KWGroupedCard { details }
                    if !viewModel.type.movesBetweenAccounts {
                        tagsCard
                    }
                    if viewModel.keepsRecordedRate {
                        Text("Edits keep the rate this transaction was logged with.", bundle: #bundle)
                            .font(KWTextStyle.captionSm.font)
                            .foregroundStyle(KWColor.Text.muted)
                    }
                    if let error = viewModel.errorMessage {
                        Text(error).font(KWTextStyle.caption.font).foregroundStyle(KWColor.State.negative)
                    }
                }
                .padding(.horizontal, KWLayout.gutter)
                .padding(.top, KWLayout.safeTop)
                .padding(.bottom, KWSpacing.md)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            saveActions
        }
        .ignoresSafeArea(.container, edges: [.top, .bottom])
        .onAppear { viewModel.prefillDescription() }
        .background(KWColor.Surface.bg)
        .foregroundStyle(KWColor.Text.primary)
        .sheet(isPresented: $isPickingDate) {
            datePicker
                .presentationDetents([.medium])
                .presentationBackground(KWColor.Surface.surface)
        }
        .sheet(isPresented: $isEditingNote) {
            NoteSheet(note: $viewModel.note) { isEditingNote = false }
        }
        .alert(
            viewModel.ruleOffer?.title ?? "",
            isPresented: isOfferingRule,
            presenting: viewModel.ruleOffer,
        ) { _ in
            Button { Task { await viewModel.acceptRuleOffer() } } label: { Text("Create rule", bundle: #bundle) }
            Button(role: .cancel) { viewModel.declineRuleOffer() } label: { Text("Not now", bundle: #bundle) }
        }
    }
}

extension ReviewView {
    /// An edit opens here, so it closes the flow and says what it is; a new movement goes back a step.
    @ViewBuilder
    private var header: some View {
        if viewModel.isEditing {
            HStack(spacing: KWSpacing.sm) {
                KWCircleButton(.close, accessibilityLabel: String(localized: "Close", bundle: #bundle), action: onBack)
                Text("Edit transaction", bundle: #bundle)
                    .font(KWTextStyle.heading.font)
                    .frame(maxWidth: .infinity)
                    .padding(.trailing, 52)
                    .accessibilityAddTraits(.isHeader)
            }
        } else {
            KWFlowHeader(.back, progress: viewModel.progress(of: .review), action: onBack)
        }
    }

    private var isOfferingRule: Binding<Bool> {
        Binding(get: { viewModel.ruleOffer != nil }, set: { _ in })
    }

    /// Slide to save, or save as a draft. An edit saves with one button, like the web, since the
    /// person already reviewed it once.
    @ViewBuilder
    private var saveActions: some View {
        if viewModel.isEditing {
            Button {
                KWKeyboard.dismiss()
                Task { await viewModel.saveChanges() }
            } label: {
                Text("Save changes", bundle: #bundle)
            }
            .buttonStyle(.kw(.primary, size: .regular))
            .disabled(!viewModel.canSave)
            .padding(.horizontal, KWLayout.gutter)
            .padding(.top, KWSpacing.sm)
            .padding(.bottom, 34)
        } else {
            newMovementActions
        }
    }

    @ViewBuilder
    private var newMovementActions: some View {
        KWSwipeToConfirm(viewModel.confirmTitle, accessibilityLabel: viewModel.saveTitle) {
            KWKeyboard.dismiss()
            Task {
                await viewModel.save()
                if viewModel.saved == nil {
                    attempt += 1
                }
            }
        }
        .id(attempt)
        .disabled(!viewModel.canSave)
        .padding(.horizontal, KWLayout.gutter)
        .padding(.top, KWSpacing.sm)
        // Not slid on purpose: a draft doesn't move money yet, so one tap is enough.
        Button {
            KWKeyboard.dismiss()
            Task { await viewModel.save(asDraft: true) }
        } label: {
            Text("Save as draft", bundle: #bundle)
        }
        .buttonStyle(KWButtonStyle(.plain, size: .text, height: 44))
        .disabled(!viewModel.canSave)
        .padding(.bottom, 24)
    }

    private var datePicker: some View {
        DatePicker(selection: $viewModel.date, displayedComponents: [.date]) {
            Text("Date", bundle: #bundle)
        }
        .datePickerStyle(.graphical)
        .padding(KWLayout.gutter)
    }

    // MARK: Summary card

    private var summaryCard: some View {
        VStack(spacing: KWSpacing.sm) {
            Text(viewModel.reviewTitle)
                .font(KWTextStyle.label.font.weight(.regular))
                .foregroundStyle(KWColor.Text.muted)
                .padding(.top, 34)
            HStack(spacing: KWSpacing.xs) {
                Text(viewModel.reviewAmount)
                    .font(.kw(40, weight: 800, relativeTo: .largeTitle))
                    .tracking(-1.2)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Button(action: viewModel.editAmount) {
                    KWIconView(.pencil, size: 18, lineWidth: 2)
                        .foregroundStyle(KWColor.Brand.link)
                        .frame(width: 36, height: 36)
                        .background(KWColor.Surface.surface2, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Edit amount", bundle: #bundle))
            }
            if let conversion = viewModel.conversionLine, viewModel.type.movesBetweenAccounts {
                Text(conversion)
                    .font(KWTextStyle.captionSm.font)
                    .foregroundStyle(KWColor.Text.muted)
                    .multilineTextAlignment(.center)
            }
            parties.padding(.top, KWSpacing.xs)
        }
        .padding(KWSpacing.sm)
        .frame(maxWidth: .infinity)
        .background(KWColor.Surface.surface.opacity(0.55), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(alignment: .top) { badge.offset(y: -28) }
    }

    /// Each end of the movement, tappable to go back and change it.
    private var parties: some View {
        VStack(spacing: KWSpacing.xs) {
            if let category = viewModel.category, !viewModel.type.movesBetweenAccounts {
                Button(action: viewModel.editCategory) {
                    AccountRowCard(
                        title: CategoryDisplay.name(of: category),
                        detail: nil,
                        caption: String(localized: "Category", bundle: #bundle),
                        leading: { categoryTile(category) },
                        trailing: { editChevron },
                    )
                }
                .buttonStyle(.plain)
                if let hint = viewModel.ruleHint {
                    Text(hint)
                        .font(KWTextStyle.captionSm.font)
                        .foregroundStyle(KWColor.Text.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if let from = viewModel.fromParty {
                Button(action: viewModel.editSource) { party(from) }.buttonStyle(.plain)
            }
            if let toParty = viewModel.toParty {
                Button(action: viewModel.editSource) { party(toParty) }.buttonStyle(.plain)
            }
        }
    }

    private var badge: some View {
        Group {
            if viewModel.type.movesBetweenAccounts {
                KWIconView(.transfer, size: 26)
            } else {
                CategorySymbol(viewModel.category, size: 26)
            }
        }
        .frame(width: 56, height: 56)
        .background(KWColor.Surface.surface2, in: Circle())
        .overlay(Circle().strokeBorder(KWColor.Surface.bg, lineWidth: 4))
        .accessibilityHidden(true)
    }

    /// Sized like the card thumbnails, so the category row lines up with the account rows.
    private func categoryTile(_ category: TransactionCategory) -> some View {
        CategorySymbol(category, size: 20)
            .frame(width: 58, height: 37)
            .background(KWColor.Surface.surface2, in: RoundedRectangle(cornerRadius: 6))
            .accessibilityHidden(true)
    }

    private func party(_ party: CreateTransactionViewModel.Party) -> some View {
        AccountRowCard(thumbnail: party.thumbnail, title: party.title, detail: party.detail, caption: party.caption) { editChevron }
    }

    private var editChevron: some View {
        KWIconView(.chevronRight, size: 16).foregroundStyle(KWColor.Text.muted)
    }

    // MARK: Details

    @ViewBuilder
    private var details: some View {
        HStack(spacing: KWSpacing.sm) {
            Text("Description", bundle: #bundle).font(KWTextStyle.body.font).foregroundStyle(KWColor.Text.secondary)
            TextField(viewModel.descriptionPlaceholder, text: $viewModel.description)
                .font(.kw(15, weight: 600))
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 13)
        Button { isPickingDate = true } label: {
            KWValueRow(String(localized: "Date", bundle: #bundle), value: "\(viewModel.dayLabel(viewModel.date)) ›")
        }
        .buttonStyle(.plain)
        if viewModel.isEditing {
            draftRow
        } else {
            repeatRow
        }
        Button { isEditingNote = true } label: {
            KWValueRow(String(localized: "Note", bundle: #bundle), value: noteValue)
        }
        .buttonStyle(.plain)
        if viewModel.showsDebitedField {
            debitedRow
        }
    }

    /// "#chips" besides the category, with the tags already used offered first.
    private var tagsCard: some View {
        VStack(alignment: .leading, spacing: KWSpacing.xxs) {
            Text("Tags", bundle: #bundle)
                .font(KWTextStyle.label.font)
                .foregroundStyle(KWColor.Text.muted)
            KWGroupedCard {
                TagEditor(tags: $viewModel.tags, usage: viewModel.tagUsage)
            }
        }
    }

    /// "Repeat": saving also creates a recurring rule that leaves drafts on the next dates.
    private var repeatRow: some View {
        Menu {
            Picker(selection: $viewModel.repeatFrequency) {
                ForEach(viewModel.repeatOptions, id: \.value) { option in
                    Text(option.title).tag(option.value)
                }
            } label: {
                EmptyView()
            }
        } label: {
            KWValueRow(String(localized: "Repeat", bundle: #bundle), value: "\(viewModel.repeatTitle) ›")
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// "Save as draft" while editing: a draft stays out of balances until it's confirmed.
    private var draftRow: some View {
        Toggle(isOn: $viewModel.isDraft) {
            Text("Save as draft", bundle: #bundle)
                .font(KWTextStyle.body.font)
                .foregroundStyle(KWColor.Text.secondary)
        }
        .toggleStyle(.kw)
        .padding(.vertical, 9)
    }

    private var noteValue: String {
        let note = viewModel.note.trimmingCharacters(in: .whitespacesAndNewlines)
        return note.isEmpty ? String(localized: "Add ›", bundle: #bundle) : note
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
}
