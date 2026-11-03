import CreateTransactionDomain
import Domain
import Foundation
import SharedPresentation

/// Rows of the payment-method step.
public struct MethodRow: Identifiable, Hashable, Sendable {
    public enum Thumbnail: Hashable, Sendable {
        case card(CardColor?)
        case transfer
        case cash
    }

    public let source: PaymentSource
    public let title: String
    public let subtitle: String?
    public let thumbnail: Thumbnail
    public var id: PaymentSource { source }
}

public struct MethodGroup: Identifiable, Hashable, Sendable {
    public let title: String
    public let rows: [MethodRow]
    public var id: String { title }
}

extension CreateTransactionViewModel {
    /// The two most recently used accounts get their own section with every method; the rest are
    /// grouped by what they are (bank accounts, cash, credit cards), one row per method.
    public var methodGroups: [MethodGroup] {
        guard let context else { return [] }
        let ranked = context.accounts
            .filter { kind != .transfer || $0.id != destinationAccountID }
            .sorted { lastUse(of: $0, in: context) > lastUse(of: $1, in: context) }
        var groups = ranked.prefix(2).compactMap { account -> MethodGroup? in
            let rows = sources(of: account, in: context).filter(isUsable).map { row(for: $0, in: context, grouped: true) }
            return rows.isEmpty ? nil : MethodGroup(title: groupTitle(account, context: context), rows: rows)
        }
        let others = Array(ranked.dropFirst(2))
        for accountKind in [AccountKind.deposit, .cash, .credit] {
            let rows = others.filter { $0.kind == accountKind }.flatMap { sources(of: $0, in: context) }.filter(isUsable)
                .map { row(for: $0, in: context, grouped: false) }
            if !rows.isEmpty {
                groups.append(MethodGroup(title: otherGroupTitle(accountKind), rows: rows))
            }
        }
        return groups
    }

    public var methodTitle: String {
        switch kind {
        case .expense: String(localized: "How did you pay?", bundle: #bundle)
        case .income: String(localized: "Where did you receive it?", bundle: #bundle)
        case .transfer: String(localized: "Where is it leaving from?", bundle: #bundle)
        }
    }

    public var methodMessage: String {
        kind == .income
            ? String(localized: "The method decides which account increases.", bundle: #bundle)
            : String(localized: "The method decides which account is charged.", bundle: #bundle)
    }

    /// "Restaurants · Debit •••• 3922".
    public var reviewSubtitle: String {
        let first = kind == .transfer
            ? destinationAccount.map(CardDisplay.name(of:)).map { String(localized: "To \($0)", bundle: #bundle) }
            : category.map(CategoryDisplay.name(of:))
        return [first, sourceTitle].compactMap(\.self).joined(separator: " · ")
    }

    public var sourceTitle: String? {
        guard let context, let source else { return nil }
        // Same wording the movement will have in lists once saved.
        if case let .card(id) = source, let card = context.card(id) {
            return CardDisplay.methodTitle(card, account: context.account(card.accountID))
        }
        return row(for: source, in: context, grouped: false).title
    }

    public var plannedLabel: String {
        switch kind {
        case .income: String(localized: "It's a planned income", bundle: #bundle)
        case .transfer: String(localized: "It's a planned transfer", bundle: #bundle)
        case .expense: String(localized: "It's a planned expense", bundle: #bundle)
        }
    }

    public var plannedHint: String {
        isPlanned
            ? String(localized: "Doesn't count until confirmed", bundle: #bundle)
            : String(localized: "Already happened: counts in balances", bundle: #bundle)
    }

    public var saveTitle: String {
        if isPlanned {
            return String(localized: "Save as planned", bundle: #bundle)
        }
        return switch type {
        case .expense: String(localized: "Save expense", bundle: #bundle)
        case .income: String(localized: "Save income", bundle: #bundle)
        case .transfer: String(localized: "Save transfer", bundle: #bundle)
        case .withdrawal: String(localized: "Save withdrawal", bundle: #bundle)
        case .cardPayment: String(localized: "Save card payment", bundle: #bundle)
        }
    }

    /// "Bank One Savings (USD)".
    public func accountLabel(_ account: Account?) -> String {
        guard let account else { return "—" }
        return "\(CardDisplay.name(of: account)) (\(currencyList(account)))"
    }

    /// "Today, Nov 2" / "Yesterday, Nov 1" / "Oct 28", in the person's language.
    public func dayLabel(_ value: Date) -> String {
        // Spanish abbreviates months with a trailing dot ("nov."), which reads badly mid-sentence.
        let day = value.formatted(.dateTime.day().month(.abbreviated))
            .replacingOccurrences(of: ".", with: "")
        if calendar.isDate(value, inSameDayAs: now()) {
            return String(localized: "Today, \(day)", bundle: #bundle)
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now()), calendar.isDate(value, inSameDayAs: yesterday) {
            return String(localized: "Yesterday, \(day)", bundle: #bundle)
        }
        return day
    }

    public func timeLabel(_ value: Date) -> String {
        value.formatted(.dateTime.hour().minute())
    }

    // MARK: Private

    private func sources(of account: Account, in context: TransactionContext) -> [PaymentSource] {
        let cards = context.cards.filter { $0.accountID == account.id }
        guard !cards.isEmpty else { return [.account(account.id)] }
        let order: [CardKind] = [.debit, .creditHolder, .creditAdditional, .transfer]
        return cards.sorted { (order.firstIndex(of: $0.kind) ?? 0) < (order.firstIndex(of: $1.kind) ?? 0) }.map { .card($0.id) }
    }

    /// "USD and NIO" / "USD y NIO": the list joiner follows the person's language.
    private func currencyList(_ account: Account) -> String {
        account.currencies.formatted(.list(type: .and))
    }

    private func otherGroupTitle(_ kind: AccountKind) -> String {
        switch kind {
        case .deposit: String(localized: "Bank accounts", bundle: #bundle)
        case .cash: String(localized: "Cash", bundle: #bundle)
        case .credit: String(localized: "Credit cards", bundle: #bundle)
        }
    }

    private func groupTitle(_ account: Account, context: TransactionContext) -> String {
        if account.kind == .credit, let holder = context.cards.first(where: { $0.accountID == account.id && $0.kind == .creditHolder }) {
            let network = CardDisplay.networkName(holder.network)
            let lastFour = holder.lastFour ?? ""
            return String(localized: "\(network) •••• \(lastFour) · credit", bundle: #bundle)
        }
        return "\(CardDisplay.name(of: account)) · \(currencyList(account))"
    }

    private func additionalRow(source: PaymentSource, card: Card, context: TransactionContext) -> MethodRow {
        let additional = String(localized: "Additional", bundle: #bundle)
        let remaining = context.additionalUsage[card.id]?.remaining.map {
            let amount = formatter.string($0, fractionDigits: 0)
            return String(localized: "\(amount) left", bundle: #bundle)
        }
        return MethodRow(
            source: source,
            title: card.additional?.holderName ?? additional,
            subtitle: [additional, remaining].compactMap(\.self).joined(separator: " · "),
            thumbnail: .card(card.color),
        )
    }

    private func row(for source: PaymentSource, in context: TransactionContext, grouped: Bool) -> MethodRow {
        switch source {
        case let .account(id):
            // Named like the movement will read in lists; the subtitle adds what's in it rather
            // than repeating the section header.
            let balance = context.balances[id]?.first.map { formatter.string($0, fractionDigits: 0) }
            return MethodRow(
                source: source,
                title: context.account(id).map(CardDisplay.name(of:)) ?? String(localized: "Cash", bundle: #bundle),
                subtitle: balance.map { String(localized: "\($0) available", bundle: #bundle) },
                thumbnail: .cash,
            )
        case let .card(id):
            guard let card = context.card(id) else { return MethodRow(source: source, title: "", subtitle: nil, thumbnail: .transfer) }
            let account = context.account(card.accountID)
            let lastFour = card.lastFour ?? ""
            switch card.kind {
            case .debit:
                let subtitle = grouped
                    ? usedLabel(context.lastUsed[source])
                    : account.map { "\(CardDisplay.name(of: $0)) · \(currencyList($0))" }
                return MethodRow(
                    source: source,
                    title: String(localized: "Debit •••• \(lastFour)", bundle: #bundle),
                    subtitle: subtitle,
                    thumbnail: .card(card.color),
                )
            case .transfer:
                // Rent paid by transfer or a direct debit: money leaves the account with no card.
                let subtitle = grouped
                    ? String(localized: "Charged directly to the account", bundle: #bundle)
                    : account.map { String(localized: "Charged directly to \(CardDisplay.name(of: $0))", bundle: #bundle) }
                return MethodRow(
                    source: source, title: String(localized: "Bank transfer", bundle: #bundle),
                    subtitle: subtitle, thumbnail: .transfer,
                )
            case .creditHolder:
                // Inside its own section the card sits next to its additionals, so it reads as the main one.
                return grouped
                    ? MethodRow(
                        source: source, title: String(localized: "Main card", bundle: #bundle),
                        subtitle: holderSubtitle(account) ?? usedLabel(context.lastUsed[source]), thumbnail: .card(card.color),
                    )
                    : MethodRow(
                        source: source, title: CardDisplay.cardNumber(card),
                        subtitle: holderSubtitle(account) ?? account.map(CardDisplay.name(of:)), thumbnail: .card(card.color),
                    )
            case .creditAdditional:
                return additionalRow(source: source, card: card, context: context)
            }
        }
    }

    /// "Purchase in NIO → debt in NIO" on dual cards, where the currency picks the debt.
    private func holderSubtitle(_ account: Account?) -> String? {
        guard let account, account.currencies.count > 1 else { return nil }
        let debt = account.currencies.contains(currency) ? currency : account.currencies[0]
        let purchase = currency
        return String(localized: "Purchase in \(purchase) → debt in \(debt)", bundle: #bundle)
    }

    private func usedLabel(_ date: Date?) -> String? {
        guard let date else { return nil }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now())).day ?? 0
        return switch days {
        case ..<1: String(localized: "Used today", bundle: #bundle)
        case 1: String(localized: "Used yesterday", bundle: #bundle)
        default: String(localized: "Used \(days) days ago", bundle: #bundle)
        }
    }
}
