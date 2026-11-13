import Core
import CreateTransactionDomain
import Domain
import Foundation
import Observation
import SharedPresentation

/// Drives "Create movement". Expenses and income go amount → category → payment method → review;
/// movements between the person's accounts go accounts → amount → review, as a bank's "send to
/// my own account" does. Both end on the saved receipt. The same steps edit a saved movement
/// (`Mode.edit`), opening on the review, and show a saved movement's receipt again (`Mode.receipt`).
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

    public enum Mode: Hashable, Sendable {
        /// Logging a new movement.
        case create
        /// Changing the saved movement with this id: the flow opens on its review, every step
        /// returns there, and saving closes the flow.
        case edit(UUID)
        /// The saved movement's receipt, shown again.
        case receipt(UUID)
    }

    public let mode: Mode

    /// The steps pushed on top of `rootStep`.
    public var path: [Step] = []
    public internal(set) var type: MovementType
    public internal(set) var amountText = "0"
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
    public internal(set) var saved: SavedTransaction?
    public internal(set) var isSaving = false
    public internal(set) var errorMessage: String?
    /// The movement as stored, while editing it or showing its receipt.
    public internal(set) var original: Transaction?
    /// Editing only: the "Save as draft" switch, on while it doesn't count toward balances yet.
    public var isDraft = false
    /// Shown after an edit that changed the category, until the person answers.
    public internal(set) var ruleOffer: RuleOffer?
    /// What the screen underneath says once an edit closes ("Saved", "Rule saved").
    public internal(set) var completionNotice: String?
    /// Set when an edit is done, so the flow closes itself.
    public internal(set) var isFinished = false
    /// Where "Save image" stands for the current receipt.
    public internal(set) var receiptImageStatus: ReceiptImageStatus = .idle
    /// The id the next saved movement gets, or the one being edited.
    var movementID: UUID
    /// The id of the rule "Repeat" saves with it.
    private var recurringRuleID: UUID

    let formatter = CurrencyFormatter()
    let calendar: Calendar
    let now: () -> Date
    private let getContext: (any GetTransactionContextUseCase)?
    private let saveTransaction: (any SaveTransactionUseCase)?
    /// Editing and showing a saved receipt only.
    let getStored: (any GetStoredTransactionUseCase)?
    let updateTransaction: (any UpdateTransactionUseCase)?
    /// "Always use … for …?" after an edit; without it the offer never shows.
    let manageRules: (any ManageCategorizationRulesUseCase)?
    private let makeID: () -> UUID
    let saveCategory: (any SaveCategoryUseCase)?
    /// Without one the receipt offers sharing only.
    let receiptSaver: (any ReceiptImageSaving)?
    static let maxAmountLength = 9
    /// Four rows of three tiles fit above the fold; past that the grid collapses behind "See all".
    static let categorySlots = 12

    /// The convenience initializers in `+Init` pick the mode and its use cases.
    init(
        mode: Mode,
        useCases: UseCases,
        saveCategory: (any SaveCategoryUseCase)?,
        receiptSaver: (any ReceiptImageSaving)?,
        type: MovementType,
        calendar: Calendar,
        now: @escaping () -> Date,
        makeID: @escaping () -> UUID,
    ) {
        self.mode = mode
        getContext = useCases.getContext
        saveTransaction = useCases.save
        getStored = useCases.getStored
        updateTransaction = useCases.update
        manageRules = useCases.manageRules
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

    /// The first screen: transfers start by choosing the accounts, the rest by the amount. An edit
    /// opens on the review, a receipt on itself.
    public var rootStep: Step {
        switch mode {
        case .create: type.movesBetweenAccounts ? .accounts : .amount
        case .edit: .review
        case .receipt: .saved
        }
    }

    public func load() async {
        switch mode {
        case .create: await loadNew()
        case let .edit(id), let .receipt(id): await loadStored(id)
        }
    }

    private func loadNew() async {
        guard let everything = try? await getContext?.execute() else {
            errorMessage = String(localized: "We couldn't load your accounts.", bundle: #bundle)
            return
        }
        let loaded = everything.forPickers()
        context = loaded
        // The second currency is the everyday one in the design ("C$" by default).
        currency = loaded.currencies.second ?? loaded.currencies.principal
        if type.movesBetweenAccounts {
            chooseDefaultAccounts()
        } else {
            source = source ?? loaded.lastUsedSource.map { pickerSource(for: $0, in: loaded) }
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
        if isEditing {
            // Back to the review, unless the payment method no longer fits and must be chosen again.
            path = source == nil ? [.category, .method] : []
        } else {
            path.append(.method)
        }
    }

    public var category: TransactionCategory? {
        context?.categories.first { $0.id == categoryID }
    }

    // MARK: Payment method

    public func selectSource(_ newSource: PaymentSource) {
        source = newSource
        debitedText = ""
        if isEditing {
            path = []
        } else {
            path.append(.review)
        }
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
        guard canSave, context != nil, let saveTransaction else { return }
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
        case .accountClosed: AccountClosingText.accountClosedError
        default: String(localized: "We couldn't save the movement. Try again.", bundle: #bundle)
        }
    }
}
