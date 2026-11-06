import Core
import Domain
import Foundation
import Observation
import RecurringDomain
import SharedPresentation

/// Creates or edits a recurring rule. Editing also shows the rule's next dates and the movements
/// it recorded, and offers pausing and deleting it.
@MainActor
@Observable
public final class RecurringRuleEditorViewModel {
    /// What pays (or receives): a card or transfer channel, or an account without one (cash).
    public enum Method: Hashable, Sendable {
        case card(UUID)
        case account(UUID)
    }

    public struct MethodOption: Identifiable, Hashable, Sendable {
        public enum Thumbnail: Hashable, Sendable {
            case card(CardColor?)
            case transfer
            case cash
        }

        public let method: Method
        public let title: String
        public let subtitle: String?
        public let thumbnail: Thumbnail
        public var id: Method { method }
    }

    public let ruleID: UUID?
    public private(set) var overview: RecurringOverview?
    public var name = ""
    public var kind = TransactionKind.expense {
        didSet { kindChanged(from: oldValue) }
    }

    public var amountText = ""
    public var currency = "USD"
    public var method: Method?
    public var destinationAccountID: UUID?
    public internal(set) var categoryID: String?
    public var frequency = RecurringFrequency.monthly
    public var interval = 1
    public var startDate: Date
    public var hasEndDate = false
    public var endDate: Date
    public var isSubscription = false
    public var autoConfirm = false
    public var note = ""
    public private(set) var isSaving = false
    public private(set) var errorMessage: String?

    private let getOverview: any GetRecurringOverviewUseCase
    private let saveRule: any SaveRecurringRuleUseCase
    private let setPaused: any SetRecurringRulePausedUseCase
    private let deleteRule: any DeleteRecurringRuleUseCase
    let calendar: Calendar
    let now: () -> Date
    let formatter = CurrencyFormatter()
    private let newID: UUID

    /// `ruleID` nil creates a rule.
    public init(
        ruleID: UUID?,
        getOverview: any GetRecurringOverviewUseCase,
        save: any SaveRecurringRuleUseCase,
        setPaused: any SetRecurringRulePausedUseCase,
        delete: any DeleteRecurringRuleUseCase,
        calendar: Calendar = .current,
        now: @escaping () -> Date = { .now },
        makeID: () -> UUID = UUID.init,
    ) {
        self.ruleID = ruleID
        self.getOverview = getOverview
        saveRule = save
        self.setPaused = setPaused
        deleteRule = delete
        self.calendar = calendar
        self.now = now
        newID = makeID()
        startDate = now()
        endDate = calendar.date(byAdding: .year, value: 1, to: now()) ?? now()
    }

    public var isEditing: Bool {
        ruleID != nil
    }

    public var rule: RecurringRule? {
        ruleID.flatMap { overview?.rule($0) }
    }

    public var isPaused: Bool {
        rule?.isPaused == true
    }

    public func load() async {
        guard let loaded = try? await getOverview.execute() else {
            errorMessage = String(localized: "We couldn't load your recurring movements.", bundle: #bundle)
            return
        }
        let isFirstLoad = overview == nil
        overview = loaded
        guard isFirstLoad else { return }
        if let rule {
            fill(from: rule)
        } else {
            currency = loaded.settings.second ?? loaded.settings.principal
            method = methodOptions.first?.method
        }
    }

    // MARK: Actions

    public var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && amount > 0 && method != nil
            && (kind == .transfer ? destinationAccountID != nil : categoryID != nil) && !isSaving
    }

    /// Returns whether it was saved.
    public func save() async -> Bool {
        guard canSave, let draft else { return false }
        isSaving = true
        defer { isSaving = false }
        do {
            try await saveRule.execute(draft)
            errorMessage = nil
            return true
        } catch {
            errorMessage = Self.message(for: error)
            return false
        }
    }

    public func togglePaused() async {
        guard let ruleID else { return }
        do {
            try await setPaused.execute(id: ruleID, isPaused: !isPaused)
            errorMessage = nil
            await load()
        } catch {
            errorMessage = String(localized: "We couldn't save it. Try again.", bundle: #bundle)
        }
    }

    /// Returns whether it was deleted.
    public func delete() async -> Bool {
        guard let ruleID else { return false }
        do {
            try await deleteRule.execute(id: ruleID)
            return true
        } catch {
            errorMessage = String(localized: "We couldn't delete it. Try again.", bundle: #bundle)
            return false
        }
    }

    var draft: RecurringRuleDraft? {
        guard let overview else { return nil }
        var accountID: UUID?
        var cardID: UUID?
        switch method {
        case let .card(id):
            cardID = id
            accountID = overview.cards.first { $0.id == id }?.accountID
        case let .account(id):
            accountID = id
        case nil:
            return nil
        }
        return RecurringRuleDraft(
            id: ruleID ?? newID,
            name: name,
            kind: kind,
            categoryID: kind == .transfer ? nil : categoryID,
            amount: amount,
            currency: currency,
            accountID: accountID,
            cardID: cardID,
            destinationAccountID: kind == .transfer ? destinationAccountID : nil,
            frequency: frequency,
            interval: interval,
            startDate: startDate,
            endDate: hasEndDate ? endDate : nil,
            isSubscription: kind == .expense && isSubscription,
            autoConfirm: autoConfirm,
            note: note,
        )
    }

    static func message(for error: DomainError) -> String {
        switch error {
        case .invalidAmount: String(localized: "Check the amount.", bundle: #bundle)
        case .missingName: String(localized: "Give it a name.", bundle: #bundle)
        case .invalidInterval: String(localized: "It can repeat every 1 to 99.", bundle: #bundle)
        case .invalidEndDate: String(localized: "It can't end before it starts.", bundle: #bundle)
        case .invalidTransferDestination: String(localized: "Choose a different destination account.", bundle: #bundle)
        default: String(localized: "We couldn't save it. Try again.", bundle: #bundle)
        }
    }

    static func unitTitle(_ frequency: RecurringFrequency) -> String {
        switch frequency {
        case .weekly: String(localized: "Weekly", bundle: #bundle)
        case .monthly: String(localized: "Monthly", bundle: #bundle)
        case .yearly: String(localized: "Yearly", bundle: #bundle)
        }
    }

    // MARK: Private

    private func fill(from rule: RecurringRule) {
        name = rule.name
        kind = rule.kind
        amountText = AmountInput.formatted(rule.amount.description) ?? rule.amount.description
        currency = rule.currency
        method = rule.cardID.map(Method.card) ?? .account(rule.accountID)
        destinationAccountID = rule.destinationAccountID
        categoryID = rule.categoryID
        frequency = rule.frequency
        interval = rule.interval
        startDate = rule.startDate
        hasEndDate = rule.endDate != nil
        endDate = rule.endDate ?? endDate
        isSubscription = rule.isSubscription
        autoConfirm = rule.autoConfirm
        note = rule.note ?? ""
    }

    /// A category of another kind, a destination outside transfers, or a method that can't send
    /// a transfer no longer fit.
    private func kindChanged(from oldKind: TransactionKind) {
        guard kind != oldKind else { return }
        if category?.kind != kind {
            categoryID = nil
        }
        if kind != .transfer {
            destinationAccountID = nil
            isSubscription = isSubscription && kind == .expense
        }
        if !methodOptions.contains(where: { $0.method == method }) {
            let account = sourceAccountID
            method = methodOptions.first { option in
                switch option.method {
                case let .card(id): overview?.cards.first { $0.id == id }?.accountID == account
                case let .account(id): id == account
                }
            }?.method ?? methodOptions.first?.method
        }
    }
}
