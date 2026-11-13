import DebtsDomain
import DesignSystem
import Domain
import SharedPresentation
import SwiftUI

/// "Debts": what the person owes and is owed (one amount per currency), their loans with the next
/// installment, and the people they lent to or borrowed from.
public struct DebtsView: View {
    @Bindable private var viewModel: DebtsViewModel
    private let onBack: () -> Void
    /// The same eye as home: hiding amounts is about who's looking at the phone, on every screen.
    @AppStorage("home.hidesBalances") private var hidesBalances = false

    public init(viewModel: DebtsViewModel, onBack: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onBack = onBack
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KWSpacing.md) {
                header
                if viewModel.state == .failed {
                    Text("We couldn't load your debts.", bundle: #bundle)
                        .foregroundStyle(KWColor.Text.muted)
                } else if let overview = viewModel.overview {
                    totals(overview.totals)
                    if viewModel.isEmpty {
                        emptyState
                    } else {
                        loans(overview.loans)
                        people(overview.debts)
                    }
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
        .sheet(item: $viewModel.loanEditor) { editor in
            LoanEditorView(viewModel: editor, onDone: finish, onClose: { viewModel.loanEditor = nil })
                .presentationDetents([.large])
                .presentationBackground(KWColor.Surface.bg)
        }
        .sheet(item: $viewModel.loanDetail, onDismiss: reload) { detail in
            LoanDetailView(
                viewModel: detail,
                hidesBalances: hidesBalances,
                onEdit: { viewModel.editLoan(detail.loan) },
                onClose: { viewModel.loanDetail = nil },
            )
            .presentationDetents([.large])
            .presentationBackground(KWColor.Surface.bg)
        }
        .sheet(item: $viewModel.debtEditor) { editor in
            DebtEditorView(viewModel: editor, onDone: finish, onClose: { viewModel.debtEditor = nil })
                .presentationDetents([.large])
                .presentationBackground(KWColor.Surface.bg)
        }
        .sheet(item: $viewModel.debtDetail, onDismiss: reload) { detail in
            DebtDetailView(
                viewModel: detail,
                hidesBalances: hidesBalances,
                onEdit: { viewModel.editDebt(detail.debt) },
                onDone: finish,
                onClose: { viewModel.debtDetail = nil },
            )
            .presentationDetents([.large])
            .presentationBackground(KWColor.Surface.bg)
        }
    }

    private func finish() {
        Task { await viewModel.sheetFinished() }
    }

    private func reload() {
        Task { await viewModel.load() }
    }

    private var header: some View {
        HStack(spacing: KWSpacing.sm) {
            KWNavigationHeader(String(localized: "Debts", bundle: #bundle), style: .large, onBack: onBack)
            KWCircleButton(
                hidesBalances ? .eyeOff : .eye,
                accessibilityLabel: hidesBalances
                    ? String(localized: "Show amounts", bundle: #bundle)
                    : String(localized: "Hide amounts", bundle: #bundle),
            ) { hidesBalances.toggle() }
            Menu {
                Button { viewModel.newLoan() } label: { Text("New loan", bundle: #bundle) }
                Button { viewModel.newDebt(.theyOweMe) } label: { Text("I lent money", bundle: #bundle) }
                Button { viewModel.newDebt(.iOwe) } label: { Text("I borrowed money", bundle: #bundle) }
            } label: {
                KWIconView(.plus, size: 20, lineWidth: 2.2)
                    .foregroundStyle(KWColor.Semantic.primaryForeground)
                    .frame(width: 40, height: 40)
                    .background(KWColor.Semantic.primary, in: Circle())
                    .contentShape(Circle())
            }
            .accessibilityLabel(Text("Add", bundle: #bundle))
        }
    }

    private func totals(_ totals: DebtTotals) -> some View {
        VStack(alignment: .leading, spacing: KWSpacing.sm) {
            HStack(alignment: .top, spacing: KWSpacing.md) {
                total(String(localized: "You owe", bundle: #bundle), lines: totals.youOwe, color: KWColor.State.negative)
                total(String(localized: "Owed to you", bundle: #bundle), lines: totals.owedToYou, color: KWColor.State.positive)
            }
            Text("Personal debts are only tracked here: they don't record movements or change your balances.", bundle: #bundle)
                .font(KWTextStyle.captionSm.font.weight(.regular))
                .foregroundStyle(KWColor.Text.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(KWSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(KWColor.Surface.surface, in: RoundedRectangle(cornerRadius: KWRadius.surface, style: .continuous))
    }

    private func total(_ title: String, lines: [Money], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(KWTextStyle.label.font).foregroundStyle(KWColor.Text.muted)
            Text(viewModel.totals(lines, hidden: hidesBalances))
                .font(.kw(17, weight: 700))
                .foregroundStyle(lines.isEmpty ? KWColor.Text.muted : color)
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var emptyState: some View {
        KWEmptyState(
            icon: .wallet,
            title: String(localized: "No debts yet", bundle: #bundle),
            message: String(
                localized: "Add a loan to follow its installments, or write down money you lent or borrowed.",
                bundle: #bundle,
            ),
            actionTitle: String(localized: "New loan", bundle: #bundle),
            action: viewModel.newLoan,
        )
        .padding(.top, 48)
    }

    @ViewBuilder
    private func loans(_ loans: [LoanProgress]) -> some View {
        if !loans.isEmpty {
            KWSectionHeader(String(localized: "Loans", bundle: #bundle), style: .large)
            KWGroupedCard {
                ForEach(loans, id: \.loan.id) { progress in
                    Button { viewModel.openLoan(progress.loan.id) } label: {
                        loanRow(progress)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func loanRow(_ progress: LoanProgress) -> some View {
        VStack(alignment: .leading, spacing: KWSpacing.xs) {
            HStack {
                KWTitleSubtitle(progress.loan.name, subtitle: progress.loan.lender)
                Spacer(minLength: KWSpacing.xs)
                Text(viewModel.loanLeft(progress, hidden: hidesBalances))
                    .font(KWTextStyle.caption.font)
                    .foregroundStyle(KWColor.Text.secondary)
                    .monospacedDigit()
            }
            KWProgressBar(paidFraction(progress), fill: progress.isPaidOff ? KWColor.State.positive : KWColor.Brand.accent)
            Text(viewModel.loanLine(progress, hidden: hidesBalances))
                .font(KWTextStyle.captionSm.font.weight(.regular))
                .foregroundStyle(progress.isNextOverdue ? KWColor.State.pending : KWColor.Text.muted)
                .monospacedDigit()
        }
        .padding(.vertical, KWSpacing.sm)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func people(_ debts: [PersonalDebt]) -> some View {
        if !debts.isEmpty {
            KWSectionHeader(String(localized: "People", bundle: #bundle), style: .large)
            KWGroupedCard {
                ForEach(debts) { debt in
                    Button { viewModel.openDebt(debt.id) } label: {
                        HStack {
                            KWTitleSubtitle(debt.person, subtitle: viewModel.debtLine(debt))
                            Spacer(minLength: KWSpacing.xs)
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(viewModel.debtAmount(debt, hidden: hidesBalances))
                                    .font(.kw(15, weight: 600))
                                    .foregroundStyle(amountColor(debt))
                                    .monospacedDigit()
                                if let due = viewModel.debtDue(debt) {
                                    DebtDueText(line: due)
                                }
                            }
                        }
                        .padding(.vertical, KWSpacing.sm)
                        .contentShape(Rectangle())
                        .accessibilityElement(children: .combine)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func amountColor(_ debt: PersonalDebt) -> Color {
        if debt.isSettled {
            return KWColor.Text.muted
        }
        return debt.direction == .theyOweMe ? KWColor.State.positive : KWColor.State.negative
    }
}

#Preview {
    DebtsPreview.list()
}
