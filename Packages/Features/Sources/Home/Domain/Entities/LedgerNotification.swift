import Domain
import Foundation

/// Something the ledger says needs attention on a given day (ADR 0012 in keepwell-api). It is
/// derived, never stored, and carries data rather than wording: the inbox and the native
/// notifications each localize it. Its `id` names one occurrence and is the same on the web, on iOS
/// and on the server, so what the person did with it (`NotificationState`) follows it everywhere.
public struct LedgerNotification: Hashable, Sendable, Identifiable {
    public enum Kind: String, Hashable, Sendable {
        case planned
        case payment
        case cutoff
        case installment
        case debt
        case renewal
        case bill
        case expiry
        case budget
        case price
        case proposal
    }

    /// What the wording needs.
    public enum Subject: Hashable, Sendable {
        case planned(Transaction)
        case payment(accountID: UUID, dueDay: Int, due: Date, daysLeft: Int)
        case cutoff(accountID: UUID)
        case installment(loanID: UUID, number: Int, daysLeft: Int)
        /// A personal debt with something left, due in `daysLeft` days (0 is today).
        case debt(PersonalDebt, due: Date, daysLeft: Int)
        case renewal(RecurringOccurrence)
        /// A recurring expense recorded as a draft, due tomorrow.
        case bill(RecurringOccurrence)
        case expiry(cardID: UUID)
        case budget(categoryID: String, level: CategoryBudgetStatus.Level)
        case price(PriceIncrease)
        case proposal(RecurringRule)
    }

    /// Where tapping it leads; each app maps it to its own screen.
    public enum Target: Hashable, Sendable {
        case transaction(UUID)
        case creditCard(accountID: UUID)
        /// A plastic's account, whatever its kind.
        case account(id: UUID)
        case debts
        case recurring
        /// Budgets are read from the month's summary.
        case summary

        /// The shape the web and the server use (`NotificationTarget`), which also travels in a
        /// push's `target` key.
        public var json: [String: String] {
            switch self {
            case let .transaction(id): ["screen": "transaction", "id": id.uuidString.lowercased()]
            case let .creditCard(accountID): ["screen": "creditCard", "accountId": accountID.uuidString.lowercased()]
            case let .account(id): ["screen": "account", "accountId": id.uuidString.lowercased()]
            case .debts: ["screen": "debts"]
            case .recurring: ["screen": "recurring"]
            case .summary: ["screen": "summary"]
            }
        }

        public init?(json: [String: Any]) {
            let uuid = { (key: String) in (json[key] as? String).flatMap(UUID.init(uuidString:)) }
            switch json["screen"] as? String {
            case "transaction": guard let id = uuid("id") else { return nil }
                self = .transaction(id)
            case "creditCard": guard let id = uuid("accountId") else { return nil }
                self = .creditCard(accountID: id)
            case "account": guard let id = uuid("accountId") else { return nil }
                self = .account(id: id)
            case "debts": self = .debts
            case "recurring": self = .recurring
            case "summary": self = .summary
            default: return nil
            }
        }

        /// The `target` a delivered notification carries: a JSON object, or JSON text.
        public init?(userInfo: [AnyHashable: Any]) {
            if let json = userInfo["target"] as? [String: Any] {
                self.init(json: json)
            } else if let text = userInfo["target"] as? String,
                      let json = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]
            {
                self.init(json: json)
            } else {
                return nil
            }
        }
    }

    /// The `notification_id` a delivered notification carries, remote or local.
    public static func id(in userInfo: [AnyHashable: Any]) -> String? {
        (userInfo["notification_id"] as? String).flatMap { $0.isEmpty ? nil : $0 }
    }

    public let id: String
    public let subject: Subject
    /// The start of the day it begins to apply: it orders and groups the inbox, and is when it is sent.
    public let date: Date
    public let target: Target

    public init(id: String, subject: Subject, date: Date, target: Target) {
        self.id = id
        self.subject = subject
        self.date = date
        self.target = target
    }

    public var kind: Kind {
        switch subject {
        case .planned: .planned
        case .payment: .payment
        case .cutoff: .cutoff
        case .installment: .installment
        case .debt: .debt
        case .renewal: .renewal
        case .bill: .bill
        case .expiry: .expiry
        case .budget: .budget
        case .price: .price
        case .proposal: .proposal
        }
    }

    /// Reports something that already happened (a budget crossed, a price that went up) or waits
    /// for an answer: it is told once, when first seen, not on a morning of its own.
    public var isOneShot: Bool {
        switch kind {
        case .budget, .price, .proposal: true
        default: false
        }
    }
}

/// A notification and the moment a local notification should show it.
public struct ScheduledNotification: Hashable, Sendable {
    public let notification: LedgerNotification
    public let fireDate: Date
}
