import Foundation

/// Where sync stands, for the account section.
public enum SyncState: Equatable, Sendable {
    case idle(lastSync: Date?, pending: Int)
    case syncing
    /// The account lacks `cloud_sync`: local use goes on; nothing is retried until /me changes.
    case needsPlan
    case signedOut
    case offline(pending: Int)
    case failed(requestID: String?)
    /// The first sync with this account found data on both sides: sync waits, and the app keeps
    /// working on this iPhone, until the person keeps one side.
    case needsChoice(SyncConflict)
}

/// How much user data one side holds, for the choice between them. Categories and settings don't
/// count: onboarding creates them on every device.
public struct SyncDataSummary: Equatable, Sendable {
    public var movements: Int
    public var accounts: Int
    public var cards: Int
    public var recurring: Int
    public var goals: Int
    public var loans: Int
    public var debts: Int
    public var rules: Int

    public init(
        movements: Int = 0,
        accounts: Int = 0,
        cards: Int = 0,
        recurring: Int = 0,
        goals: Int = 0,
        loans: Int = 0,
        debts: Int = 0,
        rules: Int = 0,
    ) {
        self.movements = movements
        self.accounts = accounts
        self.cards = cards
        self.recurring = recurring
        self.goals = goals
        self.loans = loans
        self.debts = debts
        self.rules = rules
    }

    /// The sync entities that hold user data, and what each adds to the summary. Loan payments and
    /// debt repayments count as data but have no line of their own.
    public static let userDataEntities: Set<String> = [
        "account", "card", "transaction", "recurringRule", "loan", "loanPayment", "personalDebt",
        "personalDebtRepayment", "savingsGoal", "categorizationRule",
    ]

    /// From live row counts per sync entity.
    public init(counts: [String: Int]) {
        self.init(
            movements: counts["transaction"] ?? 0,
            accounts: counts["account"] ?? 0,
            cards: counts["card"] ?? 0,
            recurring: counts["recurringRule"] ?? 0,
            goals: counts["savingsGoal"] ?? 0,
            loans: counts["loan"] ?? 0,
            debts: counts["personalDebt"] ?? 0,
            rules: counts["categorizationRule"] ?? 0,
        )
        hasOrphans = (counts["loanPayment"] ?? 0) + (counts["personalDebtRepayment"] ?? 0) > 0
    }

    /// Payments or repayments without a live parent still make it user data.
    private var hasOrphans = false

    public var hasUserData: Bool {
        hasOrphans || movements + accounts + cards + recurring + goals + loans + debts + rules > 0
    }
}

/// Both sides of a first sync that found data on each.
public struct SyncConflict: Equatable, Sendable {
    public let device: SyncDataSummary
    public let account: SyncDataSummary

    public init(device: SyncDataSummary, account: SyncDataSummary) {
        self.device = device
        self.account = account
    }
}

/// Which side a conflict keeps.
public enum SyncChoice: Equatable, Sendable {
    /// Replaces this iPhone's data with the account's.
    case useAccount
    /// Replaces the account's data, on every device, with this iPhone's.
    case keepDevice
}

/// What a sync round did.
public enum SyncRoundOutcome: Equatable, Sendable {
    case synced
    /// Nothing was sent or applied: the person has to choose a side first.
    case needsChoice(SyncConflict)
}

/// An event the server refused, kept so the person can see what stayed only on this iPhone.
public struct RejectedChange: Equatable, Sendable, Codable {
    public let entity: String
    public let entityID: String
    public let reason: String
    public let at: Date

    public init(entity: String, entityID: String, reason: String, at: Date) {
        self.entity = entity
        self.entityID = entityID
        self.reason = reason
        self.at = at
    }
}
