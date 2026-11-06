import Domain
import Foundation

/// A rule as the editor builds it. `cardID` names the payment method when there is one; the
/// account then comes from the card.
public struct RecurringRuleDraft: Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var kind: TransactionKind
    public var categoryID: String?
    public var amount: Decimal
    public var currency: String
    public var accountID: UUID?
    public var cardID: UUID?
    public var destinationAccountID: UUID?
    public var frequency: RecurringFrequency
    public var interval: Int
    public var startDate: Date
    public var endDate: Date?
    public var isSubscription: Bool
    public var autoConfirm: Bool
    public var note: String

    public init(
        id: UUID = UUID(),
        name: String = "",
        kind: TransactionKind = .expense,
        categoryID: String? = nil,
        amount: Decimal = 0,
        currency: String,
        accountID: UUID? = nil,
        cardID: UUID? = nil,
        destinationAccountID: UUID? = nil,
        frequency: RecurringFrequency = .monthly,
        interval: Int = 1,
        startDate: Date,
        endDate: Date? = nil,
        isSubscription: Bool = false,
        autoConfirm: Bool = false,
        note: String = "",
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.categoryID = categoryID
        self.amount = amount
        self.currency = currency
        self.accountID = accountID
        self.cardID = cardID
        self.destinationAccountID = destinationAccountID
        self.frequency = frequency
        self.interval = interval
        self.startDate = startDate
        self.endDate = endDate
        self.isSubscription = isSubscription
        self.autoConfirm = autoConfirm
        self.note = note
    }

    /// The editor's starting point for an existing rule.
    public init(_ rule: RecurringRule) {
        self.init(
            id: rule.id, name: rule.name, kind: rule.kind, categoryID: rule.categoryID, amount: rule.amount,
            currency: rule.currency, accountID: rule.accountID, cardID: rule.cardID,
            destinationAccountID: rule.destinationAccountID, frequency: rule.frequency, interval: rule.interval,
            startDate: rule.startDate, endDate: rule.endDate, isSubscription: rule.isSubscription,
            autoConfirm: rule.autoConfirm, note: rule.note ?? "",
        )
    }
}
