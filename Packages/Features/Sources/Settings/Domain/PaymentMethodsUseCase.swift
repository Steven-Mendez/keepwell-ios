import Domain
import Foundation

/// One account and the ways to pay from it, as Settings › Payment methods lists them.
public struct PaymentMethodGroup: Identifiable, Hashable, Sendable {
    public let account: Account
    /// Plastics first, then the transfer channel.
    public let methods: [Card]
    public var id: UUID { account.id }

    public init(account: Account, methods: [Card]) {
        self.account = account
        self.methods = methods
    }
}

/// Every payment method grouped by its account, in the order the accounts were created. Cash has
/// no method of its own, so it isn't listed.
public protocol GetPaymentMethodsUseCase: Sendable {
    func execute() async throws(DomainError) -> [PaymentMethodGroup]
}

public struct DefaultGetPaymentMethodsUseCase: GetPaymentMethodsUseCase {
    private let accounts: any AccountRepository
    private let cards: any CardRepository

    public init(accounts: any AccountRepository, cards: any CardRepository) {
        self.accounts = accounts
        self.cards = cards
    }

    public func execute() async throws(DomainError) -> [PaymentMethodGroup] {
        let cards = try await cards.fetchCards()
        return try await accounts.fetchAccounts().compactMap { account in
            let methods = cards.filter { $0.accountID == account.id }
            guard !methods.isEmpty else { return nil }
            return PaymentMethodGroup(
                account: account,
                methods: methods.filter { $0.kind != .transfer } + methods.filter { $0.kind == .transfer },
            )
        }
    }
}
