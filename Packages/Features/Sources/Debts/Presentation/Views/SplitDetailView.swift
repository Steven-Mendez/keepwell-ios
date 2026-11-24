import Core
import DebtsDomain
import DesignSystem
import Domain
import SwiftUI

/// A split expense's people: who owes what and who already paid, with "Mark as paid", "Edit split"
/// and the public link to send them.
public struct SplitDetailView: View {
    @Bindable private var viewModel: SplitDetailViewModel
    private let onEditSplit: () -> Void
    private let onClose: () -> Void
    /// The share waiting for "Mark as paid" to say where the money went.
    @State private var paying: PersonalDebt?
    /// The share waiting for "Mark as unpaid" to be confirmed (it deletes a deposited income).
    @State private var unpaying: PersonalDebt?

    public init(viewModel: SplitDetailViewModel, onEditSplit: @escaping () -> Void, onClose: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onEditSplit = onEditSplit
        self.onClose = onClose
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: KWSpacing.md) {
            KWFlowHeader(.close, action: onClose)
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Split with", bundle: #bundle).kwTextStyle(.titleSm).accessibilityAddTraits(.isHeader)
                    Text(viewModel.subtitle)
                        .font(KWTextStyle.caption.font)
                        .foregroundStyle(KWColor.Text.muted)
                        .lineLimit(1)
                }
                Spacer()
                Button(action: onEditSplit) {
                    Text("Edit split", bundle: #bundle).font(KWTextStyle.label.font).foregroundStyle(KWColor.Brand.link)
                }
                .buttonStyle(.plain)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: KWSpacing.md) {
                    if !viewModel.debts.isEmpty {
                        KWGroupedCard {
                            ForEach(viewModel.debts) { debt in
                                row(debt)
                            }
                        }
                    }
                    if let error = viewModel.errorMessage {
                        Text(error).font(KWTextStyle.caption.font).foregroundStyle(KWColor.State.negative)
                    }
                    sharing
                }
                .padding(.bottom, KWSpacing.md)
            }
            .scrollIndicators(.hidden)
        }
        .padding(.horizontal, KWLayout.gutter)
        .padding(.top, KWSpacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(KWColor.Surface.bg)
        .foregroundStyle(KWColor.Text.primary)
        .confirmationDialog(
            paying
                .map { String(localized: "\($0.person) paid you \(viewModel.formatter.string($0.remainingMoney))", bundle: #bundle) } ?? "",
            isPresented: Binding(get: { paying != nil }, set: {
                if !$0 {
                    paying = nil
                }
            }),
            titleVisibility: .visible,
            presenting: paying,
        ) { debt in
            ForEach(viewModel.depositAccounts(for: debt)) { account in
                Button {
                    Task { await viewModel.markPaid(debt, depositInto: account.id) }
                } label: {
                    Text("Deposit into \(viewModel.accountName(account))", bundle: #bundle)
                }
            }
            Button {
                Task { await viewModel.markPaid(debt, depositInto: nil) }
            } label: {
                Text("Don't deposit", bundle: #bundle)
            }
            Button(role: .cancel) {} label: {
                Text("Cancel", bundle: #bundle)
            }
        } message: { debt in
            if !viewModel.depositAccounts(for: debt).isEmpty {
                Text("A deposit changes the balance but doesn't count as income: the money only came back.", bundle: #bundle)
            }
        }
        .confirmationDialog(
            String(localized: "Mark as unpaid?", bundle: #bundle),
            isPresented: Binding(get: { unpaying != nil }, set: {
                if !$0 {
                    unpaying = nil
                }
            }),
            titleVisibility: .visible,
            presenting: unpaying,
        ) { debt in
            Button(role: .destructive) {
                Task { await viewModel.markUnpaid(debt) }
            } label: {
                Text("Mark as unpaid", bundle: #bundle)
            }
        } message: { _ in
            Text("The income it deposited is deleted too, and the balance goes back.", bundle: #bundle)
        }
        .task { await viewModel.load() }
    }

    private func row(_ debt: PersonalDebt) -> some View {
        HStack(spacing: KWSpacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(debt.person).font(KWTextStyle.body.font.weight(.semibold)).lineLimit(1)
                Text(viewModel.status(debt))
                    .font(KWTextStyle.caption.font)
                    .foregroundStyle(debt.isSettled ? KWColor.State.positive : KWColor.Text.muted)
                    .monospacedDigit()
            }
            Spacer()
            Text(viewModel.amount(debt)).font(KWTextStyle.body.font).monospacedDigit()
            if debt.isSettled {
                Button {
                    if viewModel.unpayingDeletesIncome(debt) {
                        unpaying = debt
                    } else {
                        Task { await viewModel.markUnpaid(debt) }
                    }
                } label: {
                    Text("Mark as unpaid", bundle: #bundle)
                }
                .buttonStyle(.kw(.surface, size: .small))
            } else {
                Button { paying = debt } label: {
                    Text("Mark as paid", bundle: #bundle)
                }
                .buttonStyle(.kw(.surface, size: .small))
            }
        }
        .disabled(viewModel.isSaving)
        .padding(.vertical, KWSpacing.xs)
        .accessibilityElement(children: .combine)
    }

    private var sharing: some View {
        KWGroupedCard {
            sharingContent
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 12)
        }
    }

    private var sharingContent: some View {
        VStack(alignment: .leading, spacing: KWSpacing.sm) {
            Text("Public link", bundle: #bundle).font(KWTextStyle.label.font)
            if !viewModel.canShareLink {
                Text("A link that stays up to date needs a Keepwell account. Share a summary instead.", bundle: #bundle)
                    .font(KWTextStyle.caption.font)
                    .foregroundStyle(KWColor.Text.muted)
                ShareLink(item: viewModel.summary) {
                    Text("Share summary", bundle: #bundle)
                }
                .buttonStyle(.kw(.surface, size: .small))
            } else if let url = viewModel.shareURL {
                Text("Anyone with the link sees what each person owes and who already paid. Only you can change it.", bundle: #bundle)
                    .font(KWTextStyle.caption.font)
                    .foregroundStyle(KWColor.Text.muted)
                HStack {
                    ShareLink(item: url) {
                        Text("Share link", bundle: #bundle)
                    }
                    .buttonStyle(.kw(size: .small))
                    Button { Task { await viewModel.stopSharing() } } label: {
                        Text("Stop sharing", bundle: #bundle)
                    }
                    .buttonStyle(.kw(.surface, size: .small))
                }
            } else {
                Text("Send a link so each person sees how much to pay, without an account.", bundle: #bundle)
                    .font(KWTextStyle.caption.font)
                    .foregroundStyle(KWColor.Text.muted)
                Button { Task { await viewModel.share() } } label: {
                    Text("Create link", bundle: #bundle)
                }
                .buttonStyle(.kw(size: .small))
                .disabled(viewModel.isSaving || viewModel.debts.isEmpty)
            }
        }
    }
}
