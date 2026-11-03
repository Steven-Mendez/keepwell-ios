import Core
import Domain
import Foundation
import HomeDomain
import SharedPresentation

/// One page of the hero's balance carousel: net worth first, then each account in its own
/// currency, then what the cards owe. Accounts are never added up here; only net worth converts.
struct BalancePage: Identifiable, Hashable {
    enum Kind: Hashable {
        case netWorth
        case account(UUID)
        case cardDebt
    }

    let kind: Kind
    let title: String
    let amount: Money
    /// The conversion or count under the amount.
    let caption: String?

    var id: Kind { kind }
}

/// What the hero shows: greeting, the balance carousel and hiding amounts.
extension HomeViewModel {
    /// Shown instead of every amount while balances are hidden, the way banking apps mask them.
    static let maskedAmount = "••••"

    /// "Good morning, Steven" until noon, "Good afternoon" until seven, "Good evening" otherwise;
    /// without a name, just the time of day.
    func greeting(at date: Date) -> String {
        let hour = calendar.component(.hour, from: date)
        guard let name = preferredName else {
            return switch hour {
            case 5 ..< 12: String(localized: "Good morning", bundle: #bundle)
            case 12 ..< 19: String(localized: "Good afternoon", bundle: #bundle)
            default: String(localized: "Good evening", bundle: #bundle)
            }
        }
        return switch hour {
        case 5 ..< 12: String(localized: "Good morning, \(name)", bundle: #bundle)
        case 12 ..< 19: String(localized: "Good afternoon, \(name)", bundle: #bundle)
        default: String(localized: "Good evening, \(name)", bundle: #bundle)
        }
    }

    /// "Tuesday, November 3", in the person's locale.
    func dateLine(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }

    func balancePages(_ overview: HomeOverview) -> [BalancePage] {
        let netWorth = BalancePage(
            kind: .netWorth,
            title: String(localized: "Net worth · \(overview.settings.principal)", bundle: #bundle),
            amount: overview.netWorth,
            caption: secondCurrencyLine(overview),
        )
        let accounts = overview.balances.map { line in
            BalancePage(
                kind: .account(line.account.id),
                title: CardDisplay.name(of: line.account),
                amount: line.balance,
                caption: line.balance.currency == overview.settings.principal ? nil : converted(line.balance, overview),
            )
        }
        let debt = overview.cardDebt.map { debt in
            BalancePage(
                kind: .cardDebt,
                title: String(localized: "Cards (debt)", bundle: #bundle),
                amount: debt,
                caption: nil,
            )
        }
        return [netWorth] + accounts + (debt.map { [$0] } ?? [])
    }

    /// The whole part and the cents of any amount, drawn at two sizes ("$11,157" ".46").
    func parts(_ money: Money, hidden: Bool) -> (whole: String, cents: String) {
        guard !hidden else { return (Self.maskedAmount, "") }
        let text = formatter.string(money)
        guard let dot = text.lastIndex(of: ".") else { return (text, "") }
        return (String(text[..<dot]), String(text[dot...]))
    }

    /// The text, or the mask while balances are hidden.
    func visible(_ text: String, hidden: Bool) -> String {
        hidden ? Self.maskedAmount : text
    }

    /// "≈ $95.56": a second-currency balance at the settings' rate, shown next to it, never added to others.
    private func converted(_ money: Money, _ overview: HomeOverview) -> String? {
        guard let principal = try? overview.settings.exchangeRate.convert(money, to: overview.settings.principal) else {
            return nil
        }
        return "≈ \(formatter.string(principal))"
    }
}
