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
    /// The two most recently used accounts get their own section with every method; the rest
    /// share "Otras", one row per method.
    public var methodGroups: [MethodGroup] {
        guard let context else { return [] }
        let ranked = context.accounts
            .filter { kind != .transfer || $0.id != destinationAccountID }
            .sorted { lastUse(of: $0, in: context) > lastUse(of: $1, in: context) }
        var groups = ranked.prefix(2).compactMap { account -> MethodGroup? in
            let rows = sources(of: account, in: context).filter(isUsable).map { row(for: $0, in: context, grouped: true) }
            return rows.isEmpty ? nil : MethodGroup(title: groupTitle(account, context: context), rows: rows)
        }
        let others = ranked.dropFirst(2).flatMap { sources(of: $0, in: context) }.filter(isUsable)
            .map { row(for: $0, in: context, grouped: false) }
        if !others.isEmpty {
            groups.append(MethodGroup(title: "Otras", rows: others))
        }
        return groups
    }

    public var methodTitle: String {
        switch kind {
        case .expense: "¿Con qué pagaste?"
        case .income: "¿Dónde lo recibiste?"
        case .transfer: "¿Desde dónde sale?"
        }
    }

    public var methodMessage: String {
        kind == .income ? "El medio decide qué cuenta suma." : "El medio decide qué cuenta se descuenta."
    }

    /// "Restaurantes · Débito •••• 3922".
    public var reviewSubtitle: String {
        let first = kind == .transfer ? destinationAccount.map(CardDisplay.name(of:)).map { "A \($0)" } : category?.name
        return [first, sourceTitle].compactMap(\.self).joined(separator: " · ")
    }

    public var sourceTitle: String? {
        guard let context, let source else { return nil }
        return row(for: source, in: context, grouped: false).title
    }

    public var plannedLabel: String {
        kind == .income ? "Es un ingreso previsto" : (kind == .transfer ? "Es una transferencia prevista" : "Es un gasto previsto")
    }

    public var plannedHint: String {
        isPlanned ? "No cuenta hasta confirmarlo" : "Ya pasó: cuenta en saldos"
    }

    public var saveTitle: String {
        if isPlanned {
            return "Guardar como previsto"
        }
        return switch kind {
        case .expense: "Guardar gasto"
        case .income: "Guardar ingreso"
        case .transfer: "Guardar transferencia"
        }
    }

    /// "Banco Uno Ahorro (USD)".
    public func accountLabel(_ account: Account?) -> String {
        guard let account else { return "—" }
        return "\(CardDisplay.name(of: account)) (\(account.currencies.joined(separator: " y ")))"
    }

    /// "Hoy, 2 nov" / "Ayer, 1 nov" / "28 oct".
    public func dayLabel(_ value: Date) -> String {
        let day = value.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "es")))
            .replacingOccurrences(of: ".", with: "")
        if calendar.isDate(value, inSameDayAs: now()) {
            return "Hoy, \(day)"
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now()), calendar.isDate(value, inSameDayAs: yesterday) {
            return "Ayer, \(day)"
        }
        return day
    }

    public func timeLabel(_ value: Date) -> String {
        value.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).locale(Locale(identifier: "es")))
    }

    // MARK: Private

    private func lastUse(of account: Account, in context: TransactionContext) -> Date {
        sources(of: account, in: context).compactMap { context.lastUsed[$0] }.max() ?? .distantPast
    }

    private func sources(of account: Account, in context: TransactionContext) -> [PaymentSource] {
        let cards = context.cards.filter { $0.accountID == account.id }
        guard !cards.isEmpty else { return [.account(account.id)] }
        let order: [CardKind] = [.debit, .creditHolder, .creditAdditional, .transfer]
        return cards.sorted { (order.firstIndex(of: $0.kind) ?? 0) < (order.firstIndex(of: $1.kind) ?? 0) }.map { .card($0.id) }
    }

    private func groupTitle(_ account: Account, context: TransactionContext) -> String {
        if account.kind == .credit, let holder = context.cards.first(where: { $0.accountID == account.id && $0.kind == .creditHolder }) {
            return "\(CardDisplay.networkName(holder.network)) •••• \(holder.lastFour ?? "") · crédito"
        }
        return "\(CardDisplay.name(of: account)) · \(account.currencies.joined(separator: " y "))"
    }

    private func row(for source: PaymentSource, in context: TransactionContext, grouped: Bool) -> MethodRow {
        switch source {
        case let .account(id):
            let account = context.account(id)
            let balance = context.balances[id]?.first.map { formatter.string($0, fractionDigits: 0) }
            return MethodRow(
                source: source,
                title: "Efectivo",
                subtitle: [account?.name, balance].compactMap(\.self).joined(separator: " · "),
                thumbnail: .cash,
            )
        case let .card(id):
            guard let card = context.card(id) else { return MethodRow(source: source, title: "", subtitle: nil, thumbnail: .transfer) }
            let account = context.account(card.accountID)
            switch card.kind {
            case .debit:
                let subtitle = grouped
                    ? usedLabel(context.lastUsed[source])
                    : account.map { "\(CardDisplay.name(of: $0)) · \($0.currencies.joined(separator: " y "))" }
                return MethodRow(
                    source: source,
                    title: "Débito •••• \(card.lastFour ?? "")",
                    subtitle: subtitle,
                    thumbnail: .card(card.color),
                )
            case .transfer:
                return MethodRow(
                    source: source, title: "Transferencia",
                    subtitle: grouped ? nil : account.map(CardDisplay.name(of:)), thumbnail: .transfer,
                )
            case .creditHolder:
                return grouped
                    ? MethodRow(source: source, title: "Titular", subtitle: holderSubtitle(account), thumbnail: .card(card.color))
                    : MethodRow(
                        source: source, title: "\(CardDisplay.networkName(card.network)) •••• \(card.lastFour ?? "")",
                        subtitle: "Crédito · titular", thumbnail: .card(card.color),
                    )
            case .creditAdditional:
                let remaining = context.additionalUsage[card.id]?.remaining.map { "le quedan \(formatter.string($0, fractionDigits: 0))" }
                return MethodRow(
                    source: source,
                    title: card.additional?.holderName ?? "Adicional",
                    subtitle: ["Adicional", remaining].compactMap(\.self).joined(separator: " · "),
                    thumbnail: .card(card.color),
                )
            }
        }
    }

    /// "Compra en NIO → deuda NIO" on dual cards, where the currency picks the debt.
    private func holderSubtitle(_ account: Account?) -> String? {
        guard let account, account.currencies.count > 1 else { return nil }
        let debt = account.currencies.contains(currency) ? currency : account.currencies[0]
        return "Compra en \(currency) → deuda \(debt)"
    }

    private func usedLabel(_ date: Date?) -> String? {
        guard let date else { return nil }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now())).day ?? 0
        return switch days {
        case ..<1: "Usado hoy"
        case 1: "Usado ayer"
        default: "Usado hace \(days) días"
        }
    }
}
