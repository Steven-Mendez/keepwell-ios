import Domain
import Foundation

/// "Complete card details": limit, cutoff and due day. `nil` clears a value.
public protocol UpdateCreditTermsUseCase: Sendable {
    func execute(accountID: UUID, limit: Money?, cutoffDay: Int?, dueDay: Int?) async throws(DomainError)
}

public struct DefaultUpdateCreditTermsUseCase: UpdateCreditTermsUseCase {
    private let accounts: any AccountRepository

    public init(accounts: any AccountRepository) {
        self.accounts = accounts
    }

    public func execute(accountID: UUID, limit: Money?, cutoffDay: Int?, dueDay: Int?) async throws(DomainError) {
        guard let account = try await accounts.fetchAccounts().first(where: { $0.id == accountID && $0.kind == .credit }) else {
            throw .notFound(accountID)
        }
        if let limit, limit.amount <= 0 {
            throw .invalidAmount
        }
        let terms = try CreditTerms(
            debtMode: account.creditTerms?.debtMode ?? (account.currencies.count > 1 ? .dual : .principal),
            limit: limit,
            cutoffDay: cutoffDay,
            dueDay: dueDay,
        )
        try await accounts.save(Account(
            id: account.id,
            name: account.name,
            bank: account.bank,
            kind: account.kind,
            openingBalances: account.openingBalances,
            openingDate: account.openingDate,
            creditTerms: terms,
            closedAt: account.closedAt,
        ))
    }
}
