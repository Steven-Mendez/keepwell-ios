import CreateTransactionDomain
import Domain
import Foundation
import SharedPresentation

/// The accounts step of transfers, withdrawals and card payments, and the balances every step
/// shows for the chosen accounts.
extension CreateTransactionViewModel {
    /// Accounts that can send this type of movement, the most recently used first.
    public var sourceOptions: [Account] {
        guard let context else { return [] }
        return context.accounts.filter(type.allowsSource).sorted { lastUse(of: $0, in: context) > lastUse(of: $1, in: context) }
    }

    /// Accounts that can receive it from the chosen source.
    public var destinationOptions: [Account] {
        guard let context else { return [] }
        let sourceID = sourceAccount?.id
        return context.accounts.filter { type.allowsDestination($0, from: sourceID) }
    }

    public var canContinueFromAccounts: Bool {
        guard let sourceAccount, let destinationAccountID else { return false }
        return type.allowsSource(sourceAccount) && destinationOptions.contains { $0.id == destinationAccountID }
    }

    public func continueFromAccounts() {
        guard canContinueFromAccounts else { return }
        path = isEditing ? [] : [.amount]
    }

    /// Money leaves an account through its bank transfer method when it has one, so the movement
    /// reads like the others in lists; cash has no method and moves on its own.
    public func selectSourceAccount(_ accountID: UUID) {
        guard let context, let account = context.account(accountID), type.allowsSource(account) else { return }
        let method = context.cards.first { $0.accountID == accountID && $0.kind == .transfer }
        source = method.map { .card($0.id) } ?? .account(accountID)
        debitedText = ""
        if let destinationAccountID, !destinationOptions.contains(where: { $0.id == destinationAccountID }) {
            self.destinationAccountID = nil
        }
        if destinationAccountID == nil, destinationOptions.count == 1 {
            destinationAccountID = destinationOptions.first?.id
        }
        // Typing in the currency the source holds is what makes "Available" and the review agree.
        if let held = account.currencies.first, currencyOptions.contains(held) {
            currency = held
        }
    }

    public func selectDestination(_ accountID: UUID) {
        guard destinationOptions.contains(where: { $0.id == accountID }) else { return }
        destinationAccountID = accountID
    }

    /// The source last used for this type (or the first that qualifies), and the destination asked
    /// for by a preset or, when only one account can receive, that one.
    func chooseDefaultAccounts() {
        if let presetDestinationID {
            destinationAccountID = presetDestinationID
        }
        let current = sourceAccount.flatMap { account in type.allowsSource(account) ? account.id : nil }
        let fallback = sourceOptions.first { $0.id != destinationAccountID }?.id ?? sourceOptions.first?.id
        if let chosen = current ?? fallback {
            selectSourceAccount(chosen)
        }
    }

    // MARK: Balances

    /// What the draft does to its accounts right now, from the shared balance rules.
    public var preview: MovementPreview? {
        guard let context else { return nil }
        var draft = draft
        // Before an amount is typed the balances still matter: preview a cent so the rules run.
        if draft.amount <= 0 {
            draft.amount = Decimal(string: "0.01") ?? 0
        }
        return context.preview(of: draft, calendar: calendar)
    }

    /// "Available C$7,500.00" under the amount, in the currency being typed when the account
    /// holds it. Credit cards show what is owed rather than pretending it is available money.
    public var availableLabel: String? {
        guard kind != .income, let account = sourceAccount,
              let balance = balance(of: account, in: preview?.sourceBefore) else { return nil }
        let amount = formatter.string(balance)
        return account.kind == .credit
            ? String(localized: "Card balance \(amount)", bundle: #bundle)
            : String(localized: "Available \(amount)", bundle: #bundle)
    }

    /// Recording more than a bank account or cash holds is allowed (the money may already be
    /// gone), but the amount step says so.
    public var exceedsAvailable: Bool {
        guard amount > 0, kind != .income, let account = sourceAccount, account.kind != .credit,
              let leaving = preview?.leaving, let balance = preview?.sourceBefore.first(where: { $0.currency == leaving.currency })
        else { return false }
        return leaving.amount > balance.amount
    }

    /// The sentence that keeps currencies from mixing silently. Transfers say what leaves and what
    /// arrives when either side converts; expenses and income show the equivalent, as before.
    public var conversionLine: String? {
        guard let currencies = context?.currencies, let second = currencies.second else { return nil }
        let rate = currencies.exchangeRate
        if type.movesBetweenAccounts {
            guard amount > 0, let preview, preview.convertsCurrency(from: currency) else { return nil }
            var parts: [String] = []
            if let leaving = preview.leaving, leaving.currency != currency {
                let value = formatter.string(leaving)
                parts.append(String(localized: "Leaves as \(value)", bundle: #bundle))
            }
            if let arriving = preview.arriving, arriving.currency != currency {
                let value = formatter.string(arriving)
                parts.append(String(localized: "Arrives as \(value)", bundle: #bundle))
            }
            return (parts + [formatter.rate(rate)]).joined(separator: " · ")
        }
        let other = currency == second ? currencies.principal : second
        guard let converted = try? rate.convert(Money(amount, currency), to: other) else { return nil }
        return "≈ \(formatter.string(converted)) · \(formatter.rate(rate))"
    }

    /// The card art, banknote or transfer tile that stands for an account in rows.
    public func thumbnail(of account: Account) -> MethodRow.Thumbnail {
        if account.kind == .cash {
            return .cash
        }
        let cards = context?.cards.filter { $0.accountID == account.id } ?? []
        if let card = cards.first(where: { $0.kind == .debit || $0.kind == .creditHolder }) {
            return .card(card.color)
        }
        return .transfer
    }

    /// "Visa •••• 1234 · Bank One Savings" style subtitle: the card that identifies the account.
    /// The edited movement's own closed account says it is closed instead.
    public func cardLabel(of account: Account) -> String? {
        guard account.isOpen else { return AccountClosingText.closed }
        let cards = context?.cards.filter { $0.accountID == account.id } ?? []
        guard let card = cards.first(where: { $0.kind == .debit || $0.kind == .creditHolder }) else { return nil }
        return card.kind == .debit ? CardDisplay.methodTitle(card, account: account) : CardDisplay.cardNumber(card)
    }

    func balance(of account: Account, in balances: [Money]?) -> Money? {
        let all = balances ?? context?.balances[account.id] ?? []
        return all.first { $0.currency == currency } ?? all.first
    }

    func lastUse(of account: Account, in context: TransactionContext) -> Date {
        let cards = context.cards.filter { $0.accountID == account.id }.map { PaymentSource.card($0.id) }
        return (cards + [.account(account.id)]).compactMap { context.lastUsed[$0] }.max() ?? .distantPast
    }
}
