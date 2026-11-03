import Core
import CreateTransactionDomain
import Domain
import Foundation
import Observation
import SharedPresentation

/// Drives "Create movement". Expenses and income go amount → category → payment method → review;
/// movements between the person's accounts go accounts → amount → review, as a bank's "send to
/// my own account" does. Both end on the saved receipt.
@MainActor
@Observable
public final class CreateTransactionViewModel {
    public enum Step: Hashable, Sendable {
        case accounts
        case amount
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

    /// The steps pushed on top of `rootStep`.
    public var path: [Step] = []
    public internal(set) var type: MovementType
    public private(set) var amountText = "0"
    public var currency = "USD"
    public internal(set) var context: TransactionContext?
    public private(set) var categoryID: String?
    public internal(set) var source: PaymentSource?
    public internal(set) var destinationAccountID: UUID?
    /// Set by `presetTransfer(to:)`.
    var presetDestinationID: UUID?
    /// Set by `presetCategory(_:)`.
    var presetCategoryID: String?
    public var categoryQuery = ""
    public var showsAllCategories = false
    /// The open "New category" sheet.
    public var categoryEditor: CategoryEditorViewModel?
    public var description = ""
    /// The suggestion last written into `description`, so a later category change can replace it.
    var prefilledDescription: String?
    public var date: Date
    public var debitedText = ""
    public var note = ""
    public private(set) var saved: SavedTransaction?
    public private(set) var isSaving = false
    public private(set) var errorMessage: String?
    /// Where "Save image" stands for the current receipt.
    public internal(set) var receiptImageStatus: ReceiptImageStatus = .idle
    /// The id the next saved movement gets.
    private var movementID: UUID

    let formatter = CurrencyFormatter()
    let calendar: Calendar
    let now: () -> Date
    private let getContext: any GetTransactionContextUseCase
    private let saveTransaction: any SaveTransactionUseCase
    private let makeID: () -> UUID
    let saveCategory: (any SaveCategoryUseCase)?
    /// Without one the receipt offers sharing only.
    let receiptSaver: (any ReceiptImageSaving)?
    static let maxAmountLength = 9
    /// Four rows of three tiles fit above the fold; past that the grid collapses behind "See all".
    static let categorySlots = 12

    public init(
        getContext: any GetTransactionContextUseCase,
        save: any SaveTransactionUseCase,
        saveCategory: (any SaveCategoryUseCase)? = nil,
        receiptSaver: (any ReceiptImageSaving)? = nil,
        type: MovementType = .expense,
        calendar: Calendar = .current,
        now: @escaping () -> Date = { .now },
        makeID: @escaping () -> UUID = UUID.init,
    ) {
        self.getContext = getContext
        saveTransaction = save
        self.saveCategory = saveCategory
        self.receiptSaver = receiptSaver
        self.type = type
        self.calendar = calendar
        self.now = now
        self.makeID = makeID
        date = now()
        movementID = makeID()
    }

    public var kind: TransactionKind {
        type.kind
    }

    /// The first screen: transfers start by choosing the accounts, the rest by the amount.
    public var rootStep: Step {
        type.movesBetweenAccounts ? .accounts : .amount
    }

    public func load() async {
        guard let loaded = try? await getContext.execute() else {
            errorMessage = String(localized: "We couldn't load your accounts.", bundle: #bundle)
            return
        }
        context = loaded
        // The second currency is the everyday one in the design ("C$" by default).
        currency = loaded.currencies.second ?? loaded.currencies.principal
        if type.movesBetweenAccounts {
            chooseDefaultAccounts()
        } else {
            source = source ?? loaded.lastUsedSource
        }
    }

    // MARK: Amount

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
        amount > 0 && (!type.movesBetweenAccounts || canContinueFromAccounts)
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

    public func continueFromAmount() {
        guard canContinueFromAmount else { return }
        if type.movesBetweenAccounts {
            path = [.amount, .review]
            return
        }
        path = [.category]
        if let presetCategoryID, categories.contains(where: { $0.id == presetCategoryID }) {
            selectCategory(presetCategoryID)
        }
    }

    // MARK: Category

    public func selectCategory(_ id: String) {
        categoryID = id
        if let source, !isUsable(source) {
            self.source = nil
        }
        path.append(.method)
    }

    public var category: TransactionCategory? {
        context?.categories.first { $0.id == categoryID }
    }

    // MARK: Payment method

    public func selectSource(_ newSource: PaymentSource) {
        source = newSource
        debitedText = ""
        path.append(.review)
    }

    // MARK: Review

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

    var draft: TransactionDraft {
        TransactionDraft(
            id: movementID,
            kind: kind,
            amount: amount,
            currency: currency,
            categoryID: categoryID,
            source: source,
            destinationAccountID: type.movesBetweenAccounts ? destinationAccountID : nil,
            description: resolvedDescription,
            date: date,
            actualDebitedPrincipal: debited,
            note: note,
        )
    }

    public func save() async {
        guard canSave, context != nil else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            saved = try await saveTransaction.execute(draft)
            errorMessage = nil
            path.append(.saved)
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
        date = now()
        movementID = makeID()
        saved = nil
        receiptImageStatus = .idle
        categoryQuery = ""
        showsAllCategories = false
        categoryEditor = nil
        path = []
        await load()
    }

    /// What gets stored when the person leaves the description empty. Resolved here, not in the use
    /// case, so the persisted text is in the language they were using at creation time.
    var descriptionPlaceholder: String {
        switch type {
        case .expense, .income:
            category.map(CategoryDisplay.name(of:)) ?? String(localized: "transfer.noun", defaultValue: "Transfer", bundle: #bundle)
        case .transfer: String(localized: "transfer.noun", defaultValue: "Transfer", bundle: #bundle)
        case .withdrawal: String(localized: "ATM withdrawal", bundle: #bundle)
        case .cardPayment: String(localized: "Card payment", bundle: #bundle)
        }
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
