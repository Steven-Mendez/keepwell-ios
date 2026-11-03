import Domain
import Foundation

/// What a draft would do to the accounts it touches, before it is saved: the amount step shows
/// what is available, the review shows what is left and what arrives in another currency.
public struct MovementPreview: Equatable, Sendable {
    public let sourceBefore: [Money]
    public let sourceAfter: [Money]
    /// Empty unless the draft is a transfer with a destination.
    public let destinationBefore: [Money]
    public let destinationAfter: [Money]
    /// What leaves the source, in the currency the source books it (positive).
    public let leaving: Money?
    /// What enters the destination, in the currency the destination books it (positive).
    public let arriving: Money?

    /// True when either side books the movement in a currency other than the one typed, so the
    /// flow must say so instead of moving a different currency silently.
    public func convertsCurrency(from typed: String) -> Bool {
        [leaving, arriving].compactMap(\.self).contains { $0.currency != typed }
    }
}

extension TransactionContext {
    /// Runs the draft through the same balance rules a saved movement goes through, against the
    /// current balances, so the preview can never disagree with what saving produces. Planned
    /// drafts still report what would move, but leave the balances as they are.
    public func preview(of draft: TransactionDraft, calendar: Calendar = .current) -> MovementPreview? {
        guard draft.amount > 0, let source = draft.source, let sourceID = accountID(for: source),
              let sourceAccount = account(sourceID)
        else {
            return nil
        }
        let destinationAccount = draft.kind == .transfer ? account(draft.destinationAccountID) : nil
        let movement = Transaction(
            date: draft.date,
            description: "",
            kind: draft.kind,
            categoryID: nil,
            amount: draft.amount,
            currency: draft.currency,
            accountID: sourceID,
            destinationAccountID: destinationAccount?.id,
            actualDebitedPrincipal: draft.currency == currencies.principal ? nil : draft.actualDebitedPrincipal,
            exchangeRate: currencies.exchangeRate,
        )
        let sourceSide = side(of: sourceAccount, after: movement, calendar: calendar)
        let destinationSide = destinationAccount.map { side(of: $0, after: movement, calendar: calendar) }
        return MovementPreview(
            sourceBefore: sourceSide.before,
            sourceAfter: draft.isPlanned ? sourceSide.before : sourceSide.after,
            destinationBefore: destinationSide?.before ?? [],
            destinationAfter: draft.isPlanned ? destinationSide?.before ?? [] : destinationSide?.after ?? [],
            leaving: draft.kind == .income ? nil : Self.change(from: sourceSide.before, to: sourceSide.after),
            arriving: draft.kind == .income
                ? Self.change(from: sourceSide.before, to: sourceSide.after)
                : destinationSide.flatMap { Self.change(from: $0.before, to: $0.after) },
        )
    }

    private func side(of account: Account, after movement: Transaction, calendar: Calendar) -> (before: [Money], after: [Money]) {
        let before = balances[account.id] ?? account.openingBalances
        // Starting from today's balance with an opening date in the past makes the shared rules
        // apply just this one movement on top of it.
        let current = Account(
            id: account.id,
            name: account.name,
            kind: account.kind,
            openingBalances: before,
            openingDate: .distantPast,
        )
        return (before, Balances.balance(of: current, transactions: [movement], calendar: calendar))
    }

    private static func change(from before: [Money], to after: [Money]) -> Money? {
        for (old, new) in zip(before, after) where old.amount != new.amount {
            let delta = new.amount - old.amount
            return Money(delta < 0 ? -delta : delta, new.currency)
        }
        return nil
    }
}
