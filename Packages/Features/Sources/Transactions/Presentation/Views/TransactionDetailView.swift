import DesignSystem
import Domain
import SharedPresentation
import SwiftUI

/// A movement's detail, drawn like the web's detail panel and the receipt: the kind icon, the amount
/// in its color, description and status, the actions, then the details on grouped cards. Its sheets
/// (edit, receipt, split) belong to whoever pushes it, through the closures.
public struct TransactionDetailView: View {
    /// Where the detail leads. The root decides how each one is shown.
    public struct Actions {
        public var back: () -> Void
        public var edit: (Domain.Transaction) -> Void
        public var receipt: (Domain.Transaction) -> Void
        public var split: (Domain.Transaction) -> Void
        public var openRecurringRule: (UUID) -> Void
        /// Narrows Transactions to a tag.
        public var showTag: (String) -> Void

        public init(
            back: @escaping () -> Void,
            edit: @escaping (Domain.Transaction) -> Void,
            receipt: @escaping (Domain.Transaction) -> Void,
            split: @escaping (Domain.Transaction) -> Void,
            openRecurringRule: @escaping (UUID) -> Void,
            showTag: @escaping (String) -> Void,
        ) {
            self.back = back
            self.edit = edit
            self.receipt = receipt
            self.split = split
            self.openRecurringRule = openRecurringRule
            self.showTag = showTag
        }
    }

    private let viewModel: TransactionDetailViewModel
    private let actions: Actions
    @State private var isConfirmingDeletion = false

    public init(viewModel: TransactionDetailViewModel, actions: Actions) {
        self.viewModel = viewModel
        self.actions = actions
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KWSpacing.md) {
                KWNavigationHeader(String(localized: "Transaction details", bundle: #bundle), onBack: actions.back)
                content
            }
            .padding(.horizontal, KWLayout.gutter)
            .padding(.top, KWLayout.safeTop)
            .padding(.bottom, KWSpacing.xl)
        }
        .scrollIndicators(.hidden)
        .ignoresSafeArea(edges: .top)
        .background(KWColor.Surface.bg)
        .foregroundStyle(KWColor.Text.primary)
        .toolbar(.hidden, for: .navigationBar)
        .overlay(alignment: .top) { noticeView }
        .animation(.snappy, value: viewModel.notice)
        .task { await viewModel.load() }
        .onChange(of: viewModel.isDeleted) { _, deleted in
            if deleted {
                actions.back()
            }
        }
        .confirmationDialog(
            String(localized: "Delete this transaction?", bundle: #bundle),
            isPresented: $isConfirmingDeletion,
            titleVisibility: .visible,
        ) {
            Button(role: .destructive) {
                Task { await viewModel.delete() }
            } label: {
                Text("Delete", bundle: #bundle)
            }
        } message: {
            Text("Balances update as if it never happened.", bundle: #bundle)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            ProgressView().frame(maxWidth: .infinity).padding(.top, KWSpacing.xxl)
        case .missing, .failed:
            Text("We couldn't load this movement.", bundle: #bundle)
                .font(KWTextStyle.body.font)
                .foregroundStyle(KWColor.Text.muted)
                .frame(maxWidth: .infinity)
                .padding(.top, KWSpacing.xxl)
        case .loaded:
            if let transaction = viewModel.transaction, let display = viewModel.display {
                summary(transaction, display: display)
                actionButtons(transaction)
                if let error = viewModel.actionError {
                    Text(error).font(KWTextStyle.caption.font).foregroundStyle(KWColor.State.negative)
                }
                TransactionDetailCards(viewModel: viewModel, transaction: transaction, actions: actions)
            }
        }
    }

    /// The kind icon, the amount in its color, the description and its other-currency amount.
    private func summary(_ transaction: Domain.Transaction, display: TransactionDisplay) -> some View {
        let style = display.style(of: transaction)
        return VStack(spacing: KWSpacing.xxs) {
            KWTransactionIcon(style)
                .scaleEffect(1.4)
                .padding(.bottom, KWSpacing.sm)
            Text(display.amount(of: transaction))
                .kwTextStyle(.amountLg)
                .foregroundStyle(style.amountColor)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(transaction.description)
                .font(.kw(17, weight: 600))
                .multilineTextAlignment(.center)
            if let secondary = display.secondaryAmount(of: transaction) {
                Text(secondary)
                    .font(KWTextStyle.caption.font)
                    .foregroundStyle(KWColor.Text.muted)
                    .monospacedDigit()
            }
            if !transaction.isConfirmed {
                StatusPill(confirmed: false, title: viewModel.statusText).padding(.top, KWSpacing.xxs)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, KWSpacing.sm)
        .accessibilityElement(children: .combine)
    }

    /// Confirm (drafts), Edit, Split (expenses), Receipt and Delete, as round actions.
    private func actionButtons(_ transaction: Domain.Transaction) -> some View {
        HStack(alignment: .top, spacing: KWSpacing.xs) {
            if viewModel.canConfirm {
                KWActionButton(String(localized: "Confirm", bundle: #bundle), icon: .check, style: .prominent) {
                    Task { await viewModel.confirm() }
                }
            }
            KWActionButton(
                String(localized: "Edit", bundle: #bundle),
                icon: .pencil,
                style: viewModel.canConfirm ? .neutral : .prominent,
            ) { actions.edit(transaction) }
            if viewModel.canSplit {
                KWActionButton(String(localized: "Split", bundle: #bundle), icon: .person) { actions.split(transaction) }
            }
            KWActionButton(String(localized: "Receipt", bundle: #bundle), icon: .share) { actions.receipt(transaction) }
            KWActionButton(String(localized: "Delete", bundle: #bundle), icon: .trash) { isConfirmingDeletion = true }
        }
        .padding(.vertical, KWSpacing.xs)
    }

    @ViewBuilder
    private var noticeView: some View {
        if let notice = viewModel.notice {
            Text(notice)
                .font(KWTextStyle.label.font)
                .foregroundStyle(KWColor.Text.onPositive)
                .padding(.horizontal, KWSpacing.md)
                .padding(.vertical, 10)
                .background(KWColor.State.positive, in: Capsule())
                .padding(.top, KWSpacing.xs)
                .transition(.move(edge: .top).combined(with: .opacity))
                .task {
                    try? await Task.sleep(for: .seconds(3))
                    viewModel.notice = nil
                }
        }
    }
}

/// The detail cards: when, where, kind, status and recurring rule; the rate; the note; the tags;
/// the reference.
private struct TransactionDetailCards: View {
    let viewModel: TransactionDetailViewModel
    let transaction: Domain.Transaction
    let actions: TransactionDetailView.Actions

    var body: some View {
        VStack(spacing: KWSpacing.md) {
            mainCard
            let rateRows = viewModel.rateRows
            if !rateRows.isEmpty {
                KWGroupedCard {
                    ForEach(rateRows, id: \.self) { row in
                        KWValueRow(row.label, value: row.value)
                    }
                }
            }
            if let note = transaction.note {
                labeledCard(String(localized: "Note", bundle: #bundle)) {
                    Text(note).font(KWTextStyle.body.font).fixedSize(horizontal: false, vertical: true)
                }
            }
            if !transaction.tags.isEmpty {
                tagsCard
            }
            KWGroupedCard {
                KWValueRow(String(localized: "Reference", bundle: #bundle), value: viewModel.reference)
            }
        }
    }

    /// When, what kind, where it went, its status and the recurring rule behind it.
    private var mainCard: some View {
        KWGroupedCard {
            KWValueRow(String(localized: "Date", bundle: #bundle), value: viewModel.dateText)
            KWValueRow(String(localized: "Type", bundle: #bundle), value: viewModel.kindText)
            ForEach(viewModel.routeRows, id: \.self) { row in
                KWValueRow(row.label, value: row.value)
            }
            HStack {
                Text("Status", bundle: #bundle).font(KWTextStyle.body.font).foregroundStyle(KWColor.Text.secondary)
                Spacer()
                StatusPill(confirmed: transaction.isConfirmed, title: viewModel.statusText)
            }
            .padding(.vertical, 11)
            .accessibilityElement(children: .combine)
            if let rule = viewModel.recurringRule, let text = viewModel.recurringText {
                Button { actions.openRecurringRule(rule.id) } label: {
                    KWValueRow(String(localized: "Repeats", bundle: #bundle), value: "\(text) ›")
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Each tag narrows Transactions to it.
    private var tagsCard: some View {
        labeledCard(String(localized: "Tags", bundle: #bundle)) {
            KWFlowLayout(spacing: KWSpacing.xs) {
                ForEach(transaction.tags, id: \.self) { tag in
                    TagChip(tag) { actions.showTag(tag) }
                        .accessibilityHint(Text("Show \(TagDisplay.label(tag))", bundle: #bundle))
                }
            }
        }
    }

    private func labeledCard(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        KWGroupedCard {
            VStack(alignment: .leading, spacing: KWSpacing.xs) {
                Text(title).font(KWTextStyle.caption.font).foregroundStyle(KWColor.Text.muted)
                content()
            }
            .padding(.vertical, 12)
        }
    }
}

/// "Confirmed" in green, "Draft" in the pending color, as the receipt shows the status.
private struct StatusPill: View {
    let confirmed: Bool
    let title: String

    var body: some View {
        let color = confirmed ? KWColor.State.positive : KWColor.State.pending
        Text(title)
            .font(.kw(12, weight: 700, relativeTo: .caption))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color.opacity(0.14), in: Capsule())
    }
}
