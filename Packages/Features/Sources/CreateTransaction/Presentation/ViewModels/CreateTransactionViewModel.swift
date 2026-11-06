import Core
import CreateTransactionDomain
import Domain
import Foundation
import Observation
import SharedPresentation

/// Drives "Create movement": amount and type → category (or destination for transfers) →
/// payment method → review → saved.
@MainActor
@Observable
public final class CreateTransactionViewModel {
    public enum Step: Hashable, Sendable {
        case category
        case method
        case review
        case saved
    }

    public enum Key: Hashable, Sendable {
        case digit(Int)
        case dot
        case delete
    }

    public var path: [Step] = []
    public private(set) var kind: TransactionKind
    public private(set) var amountText = "0"
    public var currency = "USD"
    public private(set) var context: TransactionContext?
    public private(set) var categoryID: String?
    public private(set) var source: PaymentSource?
    public private(set) var destinationAccountID: UUID?
    public var categoryQuery = ""
    public var showsAllCategories = false
    public var description = ""
    /// The suggestion last written into `description`, so a later category change can replace it.
    private var prefilledDescription: String?
    public var date: Date
    public var isPlanned = false
    public var isShared = false
    public var debitedText = ""
    public var note = ""
    public private(set) var saved: SavedTransaction?
    public private(set) var isSaving = false
    public private(set) var errorMessage: String?

    let formatter = CurrencyFormatter()
    let calendar: Calendar
    let now: () -> Date
    private let getContext: any GetTransactionContextUseCase
    private let saveTransaction: any SaveTransactionUseCase
    static let maxAmountLength = 9

    public init(
        getContext: any GetTransactionContextUseCase,
        save: any SaveTransactionUseCase,
        kind: TransactionKind = .expense,
        calendar: Calendar = .current,
        now: @escaping () -> Date = { .now },
    ) {
        self.getContext = getContext
        saveTransaction = save
        self.kind = kind
        self.calendar = calendar
        self.now = now
        date = now()
    }

    public func load() async {
        guard let loaded = try? await getContext.execute() else {
            errorMessage = String(localized: "We couldn't load your accounts.", bundle: #bundle)
            return
        }
        context = loaded
        // The second currency is the everyday one in the design ("C$" by default).
        currency = loaded.currencies.second ?? loaded.currencies.principal
        source = source ?? loaded.lastUsedSource
    }

    // MARK: Step 1 · Amount and type

    public func setKind(_ newKind: TransactionKind) {
        guard newKind != kind else { return }
        kind = newKind
        categoryID = nil
        destinationAccountID = nil
    }

    /// The design's keypad: one dot, at most nine characters, a lone zero is replaced, and
    /// deleting the last digit leaves "0". Cents stop at two decimals since money has no more.
    public func press(_ key: Key) {
        switch key {
        case .delete:
            amountText = amountText.count > 1 ? String(amountText.dropLast()) : "0"
        case .dot:
            if !amountText.contains("."), amountText.count < Self.maxAmountLength {
                amountText += "."
            }
        case let .digit(value):
            if let dot = amountText.firstIndex(of: "."), amountText[amountText.index(after: dot)...].count >= 2 {
                return
            }
            if amountText == "0" {
                amountText = String(value)
            } else if amountText.count < Self.maxAmountLength {
                amountText += String(value)
            }
        }
    }

    public var amount: Decimal {
        Decimal(string: amountText, locale: Locale(identifier: "en_US_POSIX")) ?? 0
    }

    public var canContinueFromAmount: Bool {
        amount > 0
    }

    public var currencyOptions: [String] {
        guard let currencies = context?.currencies else { return [currency] }
        return [currencies.second, currencies.principal].compactMap(\.self)
    }

    /// "−C$879" as typed, with the sign of the movement.
    public var amountDisplay: String {
        sign + CurrencyFormatter.symbol(for: currency) + amountText
    }

    public var sign: String {
        switch kind {
        case .expense: "−"
        case .income: "+"
        case .transfer: ""
        }
    }

    /// "≈ $24.00 · 1 USD = 36.6243 NIO".
    public var conversionLine: String? {
        guard let currencies = context?.currencies, let second = currencies.second else { return nil }
        let rate = currencies.exchangeRate
        let other = currency == second ? currencies.principal : second
        guard let converted = try? rate.convert(Money(amount, currency), to: other) else { return nil }
        return "≈ \(formatter.string(converted)) · \(formatter.rate(rate))"
    }

    public func continueFromAmount() {
        guard canContinueFromAmount else { return }
        path = [.category]
    }

    // MARK: Step 2 · Category (or destination)

    public var categories: [TransactionCategory] {
        context?.categories.filter { $0.kind == kind } ?? []
    }

    /// The grid: search results, everything after "See all N", or the eight most used.
    public var visibleCategories: [TransactionCategory] {
        let query = categoryQuery.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty {
            return categories.filter { CategoryDisplay.name(of: $0).localizedStandardContains(query) }
        }
        let usage = context?.categoryUsage ?? [:]
        let ranked = categories.enumerated()
            .sorted { lhs, rhs in
                let left = usage[lhs.element.id] ?? 0
                let right = usage[rhs.element.id] ?? 0
                return left == right ? lhs.offset < rhs.offset : left > right
            }
            .map(\.element)
        return showsAllCategories ? ranked : Array(ranked.prefix(8))
    }

    public var hasMoreCategories: Bool {
        categoryQuery.isEmpty && !showsAllCategories && categories.count > 8
    }

    public func selectCategory(_ id: String) {
        categoryID = id
        if let source, !isUsable(source) {
            self.source = nil
        }
        path.append(.method)
    }

    public var destinationOptions: [Account] {
        context?.accounts ?? []
    }

    public func selectDestination(_ id: UUID) {
        destinationAccountID = id
        if let source, context?.accountID(for: source) == id {
            self.source = nil
        }
        path.append(.method)
    }

    public var category: TransactionCategory? {
        context?.categories.first { $0.id == categoryID }
    }

    // MARK: Step 3 · Payment method

    public func selectSource(_ newSource: PaymentSource) {
        source = newSource
        debitedText = ""
        path.append(.review)
    }

    /// Additional cards that are frozen or don't allow the category can't pay; transfers can't
    /// leave from their own destination.
    public func isUsable(_ candidate: PaymentSource) -> Bool {
        guard let context else { return false }
        if case let .card(id) = candidate, let controls = context.card(id)?.additional {
            guard controls.allows(categoryID: categoryID ?? "") else { return false }
        }
        return kind != .transfer || context.accountID(for: candidate) != destinationAccountID
    }

    // MARK: Step 4 · Review

    public var sourceAccount: Account? {
        source.flatMap { context?.accountID(for: $0) }.flatMap { context?.account($0) }
    }

    public var destinationAccount: Account? {
        context?.account(destinationAccountID)
    }

    /// "USD charged by the bank" applies when paying in the second currency from an account
    /// kept in the principal currency.
    public var showsDebitedField: Bool {
        guard let principal = context?.currencies.principal, currency != principal, let account = sourceAccount else { return false }
        return account.currencies == [principal]
    }

    public var debited: Decimal? {
        showsDebitedField ? AmountInput.decimal(from: debitedText) : nil
    }

    public var canSave: Bool {
        source != nil && (debitedText.isEmpty || !showsDebitedField || debited.map { $0 > 0 } == true) && !isSaving
    }

    public func save() async {
        guard canSave, let context else { return }
        isSaving = true
        defer { isSaving = false }
        let draft = TransactionDraft(
            kind: kind,
            amount: amount,
            currency: currency,
            categoryID: categoryID,
            source: source,
            destinationAccountID: destinationAccountID,
            description: resolvedDescription,
            date: date,
            isPlanned: isPlanned,
            isShared: kind == .expense && isShared,
            actualDebitedPrincipal: debited,
            note: note,
        )
        do {
            saved = try await saveTransaction.execute(draft)
            errorMessage = nil
            path.append(.saved)
            _ = context
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    /// "Log another": a fresh movement of the same type, keeping the payment method.
    public func startOver() async {
        amountText = "0"
        categoryID = nil
        destinationAccountID = nil
        description = ""
        prefilledDescription = nil
        note = ""
        debitedText = ""
        isPlanned = false
        isShared = false
        date = now()
        saved = nil
        categoryQuery = ""
        showsAllCategories = false
        path = []
        await load()
    }

    /// What gets stored when the person leaves the description empty. Resolved here, not in the use
    /// case, so the persisted text is in the language they were using at creation time.
    var descriptionPlaceholder: String {
        category.map(CategoryDisplay.name(of:)) ?? String(localized: "transfer.noun", defaultValue: "Transfer", bundle: #bundle)
    }

    /// Shows the suggested description as real, editable text on the review step, as the design
    /// does. It follows the category while the person hasn't typed anything of their own.
    func prefillDescription() {
        let current = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard current.isEmpty || current == prefilledDescription else { return }
        description = descriptionPlaceholder
        prefilledDescription = description
    }

    private var resolvedDescription: String {
        description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? descriptionPlaceholder : description
    }

    static func message(for error: DomainError) -> String {
        switch error {
        case .invalidAmount: String(localized: "Check the amount.", bundle: #bundle)
        case .paymentMethodUnavailable: String(localized: "That card can't be used for this category.", bundle: #bundle)
        case .invalidTransferDestination: String(localized: "Choose a different destination account.", bundle: #bundle)
        default: String(localized: "We couldn't save the movement. Try again.", bundle: #bundle)
        }
    }
}
