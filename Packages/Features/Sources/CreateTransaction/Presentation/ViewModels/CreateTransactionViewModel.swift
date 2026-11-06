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
    public internal(set) var categoryID: String?
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
    public var description = "" {
        didSet { applyRules() }
    }

    /// The suggestion last written into `description`, so a later category change can replace it.
    var prefilledDescription: String?
    public var date: Date
    public var debitedText = ""
    public var note = "" {
        didSet { applyRules() }
    }

    /// Labels besides the category, normalized as they're added.
    public var tags: [String] = []
    /// The categorization rule that chose the category, for "Category from rule: Uber". Cleared when
    /// the person picks one themselves.
    public internal(set) var appliedRule: CategorizationRule?
    /// Whether the person tapped the category, rather than a widget preset or a rule choosing it.
    var categoryPickedByPerson = false
    /// What the category was before a rule changed it, to put back if the text stops matching.
    var categoryBeforeRule: String?
    /// The tags the applied rule added, so a different rule can take them back.
    var ruleAddedTags: [String] = []
    /// "Repeat": `nil` records this movement once.
    public var repeatFrequency: RecurringFrequency?
    public private(set) var saved: SavedTransaction?
    public private(set) var isSaving = false
    public private(set) var errorMessage: String?
    /// Where "Save image" stands for the current receipt.
    public internal(set) var receiptImageStatus: ReceiptImageStatus = .idle
    /// The id the next saved movement gets.
    private var movementID: UUID
    /// The id of the rule "Repeat" saves with it.
    private var recurringRuleID: UUID

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
        recurringRuleID = UUID()
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
            source = source ?? loaded.lastUsedSource.map { pickerSource(for: $0, in: loaded) }
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

    public func continueFromAmount() {
        guard canContinueFromAmount else { return }
        if type.movesBetweenAccounts {
            path = [.amount, .review]
            return
        }
        path = [.category]
        if let presetCategoryID, categories.contains(where: { $0.id == presetCategoryID }) {
            selectCategory(presetCategoryID, byPerson: false)
        }
    }

    // MARK: Category

    /// `byPerson` is false for a widget's preset: a categorization rule may still replace that one.
    public func selectCategory(_ id: String, byPerson: Bool = true) {
        categoryID = id
        if byPerson {
            categoryPickedByPerson = true
            appliedRule = nil
            ruleAddedTags = []
        }
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
            repeatFrequency: repeatFrequency,
            recurringRuleID: recurringRuleID,
            tags: tags,
        )
    }

    /// `asDraft` keeps it out of balances until it's confirmed from home or Transactions.
    public func save(asDraft: Bool = false) async {
        guard canSave, context != nil else { return }
        isSaving = true
        defer { isSaving = false }
        var draft = draft
        draft.isDraft = asDraft
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
        recurringRuleID = UUID()
        repeatFrequency = nil
        tags = []
        appliedRule = nil
        categoryPickedByPerson = false
        categoryBeforeRule = nil
        ruleAddedTags = []
        saved = nil
        receiptImageStatus = .idle
        categoryQuery = ""
        showsAllCategories = false
        categoryEditor = nil
        path = []
        await load()
    }

    private var resolvedDescription: String {
        description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? descriptionPlaceholder : description
    }

    static func message(for error: DomainError) -> String {
        switch error {
        case .invalidAmount: String(localized: "Check the amount.", bundle: #bundle)
        case .invalidTransferDestination: String(localized: "Choose a different destination account.", bundle: #bundle)
        default: String(localized: "We couldn't save the movement. Try again.", bundle: #bundle)
        }
    }
}
