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
                        summary
                        KWGroupedCard {
                            ForEach(viewModel.debts) { debt in
                                row(debt)
                            }
                        }
                        Text("Tap a person to mark their share paid.", bundle: #bundle)
                            .font(KWTextStyle.captionSm.font.weight(.regular))
                            .foregroundStyle(KWColor.Text.muted)
                    }
                    if let error = viewModel.errorMessage {
                        Text(error).font(KWTextStyle.caption.font).foregroundStyle(KWColor.State.negative)
                    }
                    SplitShareSection(viewModel: viewModel)
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
        } message: { debt in
            if viewModel.unpayingDeletesIncome(debt) {
                Text("The income it deposited is deleted too, and the balance goes back.", bundle: #bundle)
            }
        }
        .task { await viewModel.load() }
    }

    /// "C$908.87 left to collect", a bar of what came back and "1 of 3 paid"; a green "Everyone
    /// paid" once it's done.
    private var summary: some View {
        let progress = viewModel.progress
        return KWGroupedCard {
            VStack(alignment: .leading, spacing: KWSpacing.sm) {
                if progress.isDone {
                    HStack(spacing: KWSpacing.xs) {
                        KWIconView(.check, size: 14, lineWidth: 3)
                            .foregroundStyle(.white)
                            .frame(width: 24, height: 24)
                            .background(KWColor.State.positive, in: Circle())
                        Text("Everyone paid", bundle: #bundle)
                    }
                    .font(.kw(20, weight: 700))
                    .foregroundStyle(KWColor.State.positive)
                } else {
                    Text("\(progress.left) left to collect", bundle: #bundle)
                        .font(.kw(20, weight: 700))
                        .monospacedDigit()
                }
                KWProgressBar(progress.fraction, fill: progress.isDone ? KWColor.State.positive : KWColor.Brand.accent, height: 8)
                HStack {
                    Text("\(progress.collected) of \(progress.total) collected", bundle: #bundle)
                    Spacer(minLength: KWSpacing.sm)
                    Text("\(progress.paid) of \(progress.people) paid", bundle: #bundle)
                }
                .font(KWTextStyle.caption.font)
                .foregroundStyle(KWColor.Text.muted)
                .monospacedDigit()
            }
            .padding(.vertical, 12)
            .accessibilityElement(children: .combine)
        }
    }

    /// The person's initial in a circle, green with a check once their share is paid.
    private func avatar(_ debt: PersonalDebt) -> some View {
        Text(debt.person.trimmingCharacters(in: .whitespaces).first.map { String($0).uppercased() } ?? "?")
            .font(.kw(16, weight: 700))
            .foregroundStyle(debt.isSettled ? KWColor.State.positive : .white)
            .frame(width: 40, height: 40)
            .background(debt.isSettled ? KWColor.State.positive.opacity(0.14) : KWColor.Brand.b500, in: Circle())
            .overlay(alignment: .bottomTrailing) {
                if debt.isSettled {
                    KWIconView(.check, size: 9, lineWidth: 3)
                        .foregroundStyle(.white)
                        .frame(width: 16, height: 16)
                        .background(KWColor.State.positive, in: Circle())
                        .overlay(Circle().stroke(KWColor.Surface.surface, lineWidth: 2))
                        .offset(x: 2, y: 2)
                }
            }
            .accessibilityHidden(true)
    }

    /// Tapping a person marks their share paid (asking where the money went) or, once paid, unpaid.
    private func row(_ debt: PersonalDebt) -> some View {
        Button {
            if debt.isSettled {
                unpaying = debt
            } else {
                paying = debt
            }
        } label: {
            HStack(spacing: KWSpacing.sm) {
                avatar(debt)
                VStack(alignment: .leading, spacing: 2) {
                    Text(debt.person).font(KWTextStyle.body.font.weight(.semibold)).lineLimit(1)
                    Text(viewModel.status(debt))
                        .font(KWTextStyle.caption.font)
                        .foregroundStyle(debt.isSettled ? KWColor.State.positive : KWColor.Text.muted)
                        .monospacedDigit()
                }
                Spacer(minLength: KWSpacing.sm)
                Text(viewModel.amount(debt))
                    .font(.kw(17, weight: 600))
                    .monospacedDigit()
                    .strikethrough(debt.isSettled, color: KWColor.Text.muted)
                    .foregroundStyle(debt.isSettled ? KWColor.Text.muted : KWColor.Text.primary)
            }
            .padding(.vertical, KWSpacing.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isSaving)
        .accessibilityElement(children: .combine)
        .accessibilityHint(debt.isSettled ? Text("Mark as unpaid", bundle: #bundle) : Text("Mark as paid", bundle: #bundle))
    }
}
