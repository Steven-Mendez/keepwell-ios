import DesignSystem
import Domain
import SharedPresentation
import SwiftUI
import TransactionsDomain

/// Movements: search, the account filter and kind chips, the month's totals, then planned
/// movements and every confirmed one grouped by day. Long-press a row to confirm or delete it.
/// Pushed from an account or card (`onBack` set), it opens already filtered and shows that
/// account's balance on top.
public struct TransactionsView: View {
    @Bindable private var viewModel: TransactionsViewModel
    private let onNewMovement: () -> Void
    private let onBack: (() -> Void)?
    private let onOpenRecurringRule: ((UUID) -> Void)?
    private let onSplit: ((Domain.Transaction) -> Void)?
    @FocusState private var isSearchFocused: Bool
    @State private var pendingDeletion: Domain.Transaction?
    @State private var isPickingScope = false

    /// `onOpenRecurringRule` opens the rule that recorded a movement, from its menu; `onSplit`
    /// splits an expense between the person and others, who then owe their share.
    public init(
        viewModel: TransactionsViewModel,
        onBack: (() -> Void)? = nil,
        onOpenRecurringRule: ((UUID) -> Void)? = nil,
        onSplit: ((Domain.Transaction) -> Void)? = nil,
        onNewMovement: @escaping () -> Void,
    ) {
        self.viewModel = viewModel
        self.onBack = onBack
        self.onOpenRecurringRule = onOpenRecurringRule
        self.onSplit = onSplit
        self.onNewMovement = onNewMovement
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KWSpacing.md) {
                header
                if viewModel.list != nil, !viewModel.hasTransactions {
                    emptyState
                } else {
                    listContent
                }
            }
            .padding(.horizontal, KWLayout.gutter)
            .padding(.top, KWLayout.safeTop)
            .padding(.bottom, KWSpacing.md)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.immediately)
        .ignoresSafeArea(edges: .top)
        .background(KWColor.Surface.bg)
        .foregroundStyle(KWColor.Text.primary)
        .toolbar(.hidden, for: .navigationBar)
        .task { await viewModel.load() }
        .sheet(isPresented: $isPickingScope) {
            ScopePickerSheet(viewModel: viewModel) { isPickingScope = false }
                .presentationDetents([.medium, .large])
                .presentationBackground(KWColor.Surface.bg)
        }
        .onChange(of: viewModel.wantsSearchFocus, initial: true) { _, wants in
            guard wants else { return }
            isSearchFocused = true
            viewModel.wantsSearchFocus = false
        }
        .confirmationDialog(
            String(localized: "Delete this transaction?", bundle: #bundle),
            isPresented: isConfirmingDeletion,
            titleVisibility: .visible,
            presenting: pendingDeletion,
        ) { transaction in
            Button(role: .destructive) {
                Task { await viewModel.delete(transaction.id) }
            } label: {
                Text("Delete", bundle: #bundle)
            }
        } message: { _ in
            Text("Balances update as if it never happened.", bundle: #bundle)
        }
    }

    /// The scoped account's balance (when opened from an account), search, filters, totals and the days.
    @ViewBuilder
    private var listContent: some View {
        if onBack != nil, let balance = viewModel.scopeBalance {
            BalanceHeader(balance.label, amount: balance.amount, details: balance.details, alignment: .leading)
                .padding(.bottom, KWSpacing.xxs)
        }
        searchField
        chips
        monthTotals
        if let error = viewModel.actionError {
            Text(error).font(KWTextStyle.caption.font).foregroundStyle(KWColor.State.negative)
        }
        sections
    }

    private var isConfirmingDeletion: Binding<Bool> {
        Binding(get: { pendingDeletion != nil }, set: {
            if !$0 {
                pendingDeletion = nil
            }
        })
    }

    @ViewBuilder
    private var header: some View {
        if let onBack {
            KWNavigationHeader(String(localized: "Transactions", bundle: #bundle), onBack: onBack)
        } else {
            KWLargeTitleHeader(String(localized: "Transactions", bundle: #bundle)) {
                KWCircleButton(
                    .plus,
                    style: .white,
                    accessibilityLabel: String(localized: "New transaction", bundle: #bundle),
                    action: onNewMovement,
                )
            }
        }
    }

    @ViewBuilder
    private var monthTotals: some View {
        if let month = viewModel.monthTotals {
            HStack {
                Text(month.title)
                    .font(KWTextStyle.label.font.weight(.regular))
                    .foregroundStyle(KWColor.Text.muted)
                Spacer(minLength: KWSpacing.xs)
                (Text(month.spent).foregroundStyle(KWTransactionStyle.expense.amountColor)
                    + Text(verbatim: " · ").foregroundStyle(KWColor.Text.faint)
                    + Text(month.earned).foregroundStyle(KWTransactionStyle.income.amountColor))
                    .font(.kw(15, weight: 700))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(.horizontal, KWSpacing.md)
            .padding(.vertical, 14)
            .background(KWColor.Surface.surface, in: RoundedRectangle(cornerRadius: KWRadius.surface, style: .continuous))
            .accessibilityElement(children: .combine)
        }
    }

    private var emptyState: some View {
        KWEmptyState(
            icon: .list,
            title: String(localized: "No transactions yet", bundle: #bundle),
            message: String(localized: "Log your first expense, income or transfer and it shows up here.", bundle: #bundle),
            actionTitle: String(localized: "Log transaction", bundle: #bundle),
            action: onNewMovement,
        )
        .padding(.top, 120)
    }

    private var searchField: some View {
        HStack(spacing: KWSpacing.xs) {
            KWIconView(.search, size: 18)
                .foregroundStyle(KWColor.Text.muted)
            TextField(
                String(localized: "Search", bundle: #bundle),
                text: $viewModel.query,
                prompt: Text("Search merchant, note, category or #tag", bundle: #bundle).foregroundStyle(KWColor.Text.muted),
            )
            .font(KWTextStyle.body.font)
            .focused($isSearchFocused)
            .submitLabel(.search)
            .autocorrectionDisabled()
            if !viewModel.query.isEmpty {
                Button { viewModel.query = "" } label: {
                    KWIconView(.close, size: 16).foregroundStyle(KWColor.Text.muted)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Clear search", bundle: #bundle))
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 42)
        .background(KWColor.Surface.surface, in: Capsule())
    }

    private var chips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: KWSpacing.xs) {
                ScopeChip(
                    title: viewModel.scopeTitle,
                    isFiltered: viewModel.scope != .all,
                    onPick: { isPickingScope = true },
                    onClear: { viewModel.scope = .all },
                )
                Rectangle()
                    .fill(KWColor.Surface.border)
                    .frame(width: 1, height: 22)
                    .accessibilityHidden(true)
                ForEach(TransactionFilter.allCases, id: \.self) { filter in
                    KWChip(viewModel.filterTitle(filter), isSelected: viewModel.filter == filter) {
                        viewModel.filter = filter
                    }
                }
            }
            .padding(.horizontal, KWLayout.gutter)
        }
        .scrollIndicators(.hidden)
        .padding(.horizontal, -KWLayout.gutter)
    }

    @ViewBuilder
    private var sections: some View {
        let sections = viewModel.sections
        if sections.isEmpty, viewModel.list != nil {
            Group {
                if viewModel.isScopeEmpty {
                    Text("No movements here yet.", bundle: #bundle)
                } else {
                    Text("Nothing matches. Try another word or filter.", bundle: #bundle)
                }
            }
            .font(KWTextStyle.body.font)
            .foregroundStyle(KWColor.Text.muted)
            .frame(maxWidth: .infinity)
            .padding(.top, KWSpacing.xxl)
        }
        if let display = viewModel.display {
            ForEach(sections) { section in
                VStack(alignment: .leading, spacing: KWSpacing.xs) {
                    Text(section.title)
                        .font(KWTextStyle.label.font)
                        .foregroundStyle(KWColor.Text.muted)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.top, KWSpacing.xxs)
                    KWGroupedCard(horizontalPadding: 14, verticalPadding: KWSpacing.xxs) {
                        ForEach(section.transactions) { transaction in
                            row(transaction, display: display)
                        }
                    }
                }
            }
        }
    }
}

extension TransactionsView {
    private func row(_ transaction: Domain.Transaction, display: TransactionDisplay) -> some View {
        KWTransactionRow(
            display.style(of: transaction),
            title: transaction.description,
            subtitle: viewModel.subtitle(of: transaction, display: display),
            amount: display.amount(of: transaction),
            secondaryAmount: display.secondaryAmount(of: transaction),
        )
        .contentShape(Rectangle())
        .contextMenu {
            ForEach(transaction.tags, id: \.self) { tag in
                Button { viewModel.show(tag: tag) } label: {
                    Label { Text("Show \(TagDisplay.label(tag))", bundle: #bundle) } icon: { Image(systemName: "number") }
                }
            }
            if let rule = viewModel.list?.recurringRule(of: transaction), let onOpenRecurringRule {
                Button { onOpenRecurringRule(rule.id) } label: {
                    Label { Text(RecurringDisplay.badge(of: rule)) } icon: { Image(systemName: "repeat") }
                }
            }
            if transaction.kind == .expense, let onSplit {
                Button { onSplit(transaction) } label: {
                    Label { Text("Split", bundle: #bundle) } icon: { Image(systemName: "person.2") }
                }
            }
            if !transaction.isConfirmed {
                Button {
                    Task { await viewModel.confirm(transaction.id) }
                } label: {
                    Label { Text("Confirm", bundle: #bundle) } icon: { Image(systemName: "checkmark") }
                }
            }
            Button(role: .destructive) {
                pendingDeletion = transaction
            } label: {
                Label { Text("Delete", bundle: #bundle) } icon: { Image(systemName: "trash") }
            }
        }
        .accessibilityAction(named: Text("Delete", bundle: #bundle)) { pendingDeletion = transaction }
    }
}
