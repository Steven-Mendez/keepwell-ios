import Charts
import Core
import DesignSystem
import Domain
import SwiftUI
import TransactionsDomain

public struct TransactionsDashboardView: View {
    @State private var viewModel: TransactionsViewModel
    private let formatter: CurrencyFormatter
    private let onAddTransaction: () -> Void

    public init(
        viewModel: TransactionsViewModel,
        formatter: CurrencyFormatter,
        onAddTransaction: @escaping () -> Void,
    ) {
        _viewModel = State(initialValue: viewModel)
        self.formatter = formatter
        self.onAddTransaction = onAddTransaction
    }

    public var body: some View {
        List {
            Section {
                monthHeader
                summaryCard
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: KWSpacing.xs, leading: KWLayout.gutter, bottom: KWSpacing.xs, trailing: KWLayout.gutter))

            transactionsSection
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(KWColor.Surface.bg)
        .navigationTitle("Resumen")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Nuevo movimiento", systemImage: "plus", action: onAddTransaction)
                    .accessibilityIdentifier("transactions.add")
            }
        }
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
        .alert(
            "No se pudo completar",
            isPresented: Binding(get: { viewModel.actionError != nil }, set: {
                if !$0 {
                    viewModel.actionError = nil
                }
            }),
            presenting: viewModel.actionError,
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { error in
            Text(error.userMessage)
        }
    }

    // MARK: - Sections

    private var monthHeader: some View {
        HStack {
            Button("Mes anterior", systemImage: "chevron.left") {
                Task { await viewModel.showPreviousMonth() }
            }
            .labelStyle(.iconOnly)

            Spacer()
            Text(viewModel.monthStart?.formatted(.dateTime.month(.wide).year()) ?? viewModel.month.description)
                .kwTextStyle(.heading)
                .foregroundStyle(KWColor.Text.primary)
                .accessibilityIdentifier("transactions.month.title")
            Spacer()

            Button("Mes siguiente", systemImage: "chevron.right") {
                Task { await viewModel.showNextMonth() }
            }
            .labelStyle(.iconOnly)
        }
        .buttonStyle(.borderless)
        .tint(KWColor.Text.secondary)
    }

    private var summaryCard: some View {
        KWSurfaceCard {
            VStack(alignment: .leading, spacing: KWSpacing.md) {
                if viewModel.availableCurrencies.count > 1 {
                    Picker("Moneda", selection: Binding(
                        get: { viewModel.currency },
                        set: { newValue in Task { await viewModel.selectCurrency(newValue) } },
                    )) {
                        ForEach(viewModel.availableCurrencies, id: \.self) { Text($0) }
                    }
                    .pickerStyle(.segmented)
                }

                switch viewModel.state {
                case let .failed(error):
                    ContentUnavailableView(
                        "Sin datos",
                        systemImage: "exclamationmark.triangle",
                        description: Text(error.userMessage),
                    )
                default:
                    if let summary = viewModel.summary {
                        SummaryContent(summary: summary, formatter: formatter)
                    } else {
                        ProgressView().frame(maxWidth: .infinity, minHeight: 200)
                    }
                }
            }
        }
    }

    private var transactionsSection: some View {
        Section("Movimientos") {
            if viewModel.transactions.isEmpty, viewModel.state == .loaded {
                Text("Sin movimientos este mes")
                    .kwTextStyle(.body)
                    .foregroundStyle(KWColor.Text.muted)
                    .listRowBackground(KWColor.Surface.bg)
            }
            ForEach(viewModel.transactions) { transaction in
                TransactionRow(transaction: transaction, formatter: formatter)
                    .listRowBackground(KWColor.Surface.bg)
                    .swipeActions {
                        Button("Eliminar", systemImage: "trash", role: .destructive) {
                            Task { await viewModel.delete(transaction) }
                        }
                    }
            }
        }
    }
}

// MARK: - Summary

private struct SummaryContent: View {
    let summary: MonthlySummary
    let formatter: CurrencyFormatter

    var body: some View {
        VStack(alignment: .leading, spacing: KWSpacing.md) {
            VStack(alignment: .leading, spacing: KWSpacing.xxs) {
                Text("Balance neto")
                    .kwTextStyle(.caption)
                    .foregroundStyle(KWColor.Text.muted)
                Text(formatter.string(from: summary.netBalance, currencyCode: summary.currency))
                    .kwTextStyle(.amountLg)
                    .foregroundStyle(KWColor.Text.primary)
                Text(savingsRateText)
                    .kwTextStyle(.caption)
                    .foregroundStyle(KWColor.Text.secondary)
            }

            Chart(bars) { bar in
                BarMark(x: .value("Tipo", bar.label), y: .value("Monto", bar.plotValue))
                    .foregroundStyle(bar.color)
                    .cornerRadius(KWRadius.mini)
                    .annotation(position: .top) {
                        Text(formatter.string(from: bar.amount, currencyCode: summary.currency))
                            .kwTextStyle(.captionSm)
                            .foregroundStyle(KWColor.Text.secondary)
                    }
            }
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks { _ in AxisValueLabel().foregroundStyle(KWColor.Text.muted) }
            }
            .frame(height: 160)
        }
    }

    private var savingsRateText: String {
        guard let rate = summary.savingsRate else { return "Sin ingresos este mes" }
        return "Ahorro: \(rate.formatted(.percent.precision(.fractionLength(0 ... 1))))"
    }

    private var bars: [SummaryBar] {
        [
            SummaryBar(label: "Ingresos", amount: summary.totalIncome, color: KWColor.State.positive),
            SummaryBar(label: "Gastos", amount: summary.totalExpense, color: KWColor.Brand.accent),
        ]
    }
}

private struct SummaryBar: Identifiable {
    let label: String
    let amount: Decimal
    let color: Color

    var id: String { label }

    /// Swift Charts only plots floating-point values. This is the single allowed `Decimal → Double`
    /// conversion: it affects bar height only, never a displayed or stored amount.
    var plotValue: Double {
        NSDecimalNumber(decimal: amount).doubleValue
    }
}

// MARK: - Row

private struct TransactionRow: View {
    // Qualified: SwiftUI also declares a `Transaction` type.
    let transaction: TransactionsDomain.Transaction
    let formatter: CurrencyFormatter

    var body: some View {
        HStack(spacing: KWSpacing.sm) {
            Circle()
                .fill(KWColor.category(named: transaction.category.name))
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: KWSpacing.xxs) {
                Text(transaction.category.name)
                    .kwTextStyle(.label)
                    .foregroundStyle(KWColor.Text.primary)
                Text(subtitle)
                    .kwTextStyle(.captionSm)
                    .foregroundStyle(KWColor.Text.muted)
            }
            Spacer()
            Text(formatter.signedString(from: signedAmount, currencyCode: transaction.currency))
                .kwTextStyle(.label)
                .monospacedDigit()
                // HANDOFF style: expenses in white, income in green, planned in amber.
                .foregroundStyle(amountColor)
        }
        .padding(.vertical, KWSpacing.xxs)
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        let date = transaction.date.formatted(.dateTime.day().month(.abbreviated))
        let parts = [date, transaction.note, transaction.status == .planned ? "Previsto" : nil]
        return parts.compactMap(\.self).joined(separator: " · ")
    }

    private var signedAmount: Decimal {
        transaction.kind == .expense ? -transaction.amount : transaction.amount
    }

    private var amountColor: Color {
        if transaction.status == .planned {
            return KWColor.State.pending
        }
        return transaction.kind == .income ? KWColor.State.positive : KWColor.Text.primary
    }
}

#if DEBUG
import TransactionsData

#Preview("Dashboard") {
    let calendar = Calendar.current
    let month = YearMonth(containing: .now, calendar: calendar)
    let repository = InMemoryTransactionRepository(transactions: TransactionSeed.sample(for: month, calendar: calendar))
    NavigationStack {
        TransactionsDashboardView(
            viewModel: TransactionsViewModel(
                getMonthlySummary: DefaultGetMonthlySummaryUseCase(repository: repository, calendar: calendar),
                getMonthlyTransactions: DefaultGetMonthlyTransactionsUseCase(repository: repository, calendar: calendar),
                deleteTransaction: DefaultDeleteTransactionUseCase(repository: repository),
                month: month,
                currency: "USD",
                calendar: calendar,
            ),
            formatter: CurrencyFormatter(),
            onAddTransaction: {},
        )
    }
    .preferredColorScheme(.dark)
    .onAppear { KWFonts.register() }
}
#endif
