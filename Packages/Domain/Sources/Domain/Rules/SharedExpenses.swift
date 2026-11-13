import Foundation

// Shared expenses: a split movement only cost the person their part, and the repayment of a share
// that comes back into an account is that money returning, not income. Same rules as keepwell-web's
// `debtLinks`, `spendingAmountIn` and `isReimbursement` (domain/rules.ts).

/// What the personal debts say about the movements, by movement id: the "they owe me" debts split
/// from each one (`PersonalDebt.transactionID`) and the income movements that deposited a repayment
/// (`DebtRepayment.transactionID`). Build it once and pass it to the totals.
public struct DebtLinks: Sendable {
    public let shares: [UUID: [PersonalDebt]]
    public let reimbursements: Set<UUID>

    /// No debts: every movement counts whole.
    public static let empty = Self([])

    /// `deposits` adds movements known to have deposited a repayment that `debts` no longer list:
    /// those of deleted debts and repayments (`PersonalDebtRepository.fetchRepaymentDepositIDs`), so a
    /// deposit left behind by "Delete" still isn't income. Totals over the whole ledger pass them.
    public init(_ debts: [PersonalDebt], deposits: [UUID] = []) {
        var shares: [UUID: [PersonalDebt]] = [:]
        var reimbursements = Set(deposits)
        for debt in debts {
            if debt.direction == .theyOweMe, let id = debt.transactionID {
                shares[id, default: []].append(debt)
            }
            for repayment in debt.repayments {
                if let id = repayment.transactionID {
                    reimbursements.insert(id)
                }
            }
        }
        self.shares = shares
        self.reimbursements = reimbursements
    }
}

extension Transaction {
    /// The "they owe me" debts split from an expense; empty for anything else.
    public func splitDebts(_ links: DebtLinks) -> [PersonalDebt] {
        guard kind == .expense else { return [] }
        return links.shares[id] ?? []
    }

    /// Shared: an expense that has debts split from it. Old rows only carry `isShared`, which
    /// doesn't count here.
    public func isSplit(_ links: DebtLinks) -> Bool {
        !splitDebts(links).isEmpty
    }

    /// An income movement that deposited a personal-debt repayment: money coming back, not income.
    public func isReimbursement(_ links: DebtLinks) -> Bool {
        kind == .income && links.reimbursements.contains(id)
    }

    /// What the movement cost the person in `currency`: `storedAmount(in:)`, less the shares split
    /// from it (settled or not: those were never the person's spending), never below zero. `nil`
    /// when the movement itself can't be converted, as `storedAmount(in:)`. Only expenses have
    /// shares.
    public func spendingAmount(in currency: String, debts links: DebtLinks) -> Decimal? {
        guard let total = storedAmount(in: currency) else { return nil }
        let others = splitDebts(links).reduce(Decimal(0)) { $0 + ($1.share(of: self, in: currency) ?? 0) }
        return max(total - others, 0)
    }

    /// The person's spending on the movement in its principal currency (`spendingAmount(in:debts:)`).
    public func spendingAmount(debts links: DebtLinks) -> Decimal {
        spendingAmount(in: exchangeRate.principal, debts: links) ?? principalAmount
    }

    /// The movement's part of a summary total in `currency`: an expense's `spendingAmount`, an
    /// income's amount; `nil` when the stored rate can't convert it. Repayment deposits
    /// (`isReimbursement`) are skipped before this.
    func summaryAmount(in currency: String, debts links: DebtLinks) -> Decimal? {
        kind == .expense ? spendingAmount(in: currency, debts: links) : storedAmount(in: currency)
    }
}

extension Transaction {
    /// What is left of an expense to split, in its own currency: its amount less the shares the
    /// "they owe me" debts already split from it take (alive ones, settled or not; a deleted debt
    /// frees its share), never below zero. Anything else has nothing to split.
    public func splitRemaining(debts: [PersonalDebt]) -> Decimal {
        guard kind == .expense else { return 0 }
        let taken = splitDebts(DebtLinks(debts)).reduce(Decimal(0)) { taken, debt in
            taken + (debt.amount.currency == currency ? debt.amount.amount : debt.share(of: self, in: currency) ?? 0)
        }
        return max(amount - taken, 0)
    }
}

extension PersonalDebt {
    /// Whether a repayment can be deposited into an account: only on a "they owe me" debt in the
    /// ledger's principal or second currency, the ones a movement can be recorded in.
    public func canDepositRepayment(currencies: CurrencySettings) -> Bool {
        direction == .theyOweMe && (amount.currency == currencies.principal || amount.currency == currencies.second)
    }

    /// This debt's share of `transaction` in `currency`, the way the movement converts: in the
    /// movement's own currency it is that fraction of `storedAmount(in:)` (so a bank's real charge
    /// is shared alike); otherwise it converts with the movement's stored rate. `nil` when that rate
    /// can't reach `currency`, and the share is then ignored.
    public func share(of transaction: Transaction, in currency: String) -> Decimal? {
        let owed = amount.amount
        if amount.currency == transaction.currency {
            guard let total = transaction.storedAmount(in: currency), transaction.amount != 0 else { return nil }
            return owed * total / transaction.amount
        }
        if amount.currency == currency {
            return owed
        }
        return try? transaction.exchangeRate.convert(amount, to: currency).amount
    }
}
