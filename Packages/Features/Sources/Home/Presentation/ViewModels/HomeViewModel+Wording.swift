import Domain
import Foundation
import HomeDomain
import RecurringDomain
import SharedPresentation

/// The text of each reminder, shared by the notifications the system delivers and by the in-app
/// notifications list, so both say the same thing in the same words.
extension HomeViewModel {
    struct Wording: Equatable {
        let title: String
        let body: String
    }

    func paymentWording(_ account: Account, dueDay: Int, days: Int, in overview: HomeOverview) -> Wording {
        let name = cardName(of: account, in: overview)
        return Wording(
            // "Payment in 0 days" reads like a glitch on the last day to pay.
            title: days == 0
                ? String(localized: "\(name): due today", bundle: #bundle)
                : String(localized: "\(name): payment in \(days) days", bundle: #bundle),
            body: String(localized: "Pay before day \(dueDay) so it doesn't generate interest.", bundle: #bundle),
        )
    }

    func installmentWording(_ loan: Loan, number: Int, days: Int) -> Wording {
        let amount = formatter.string(from: loan.installmentAmount, currencyCode: loan.borrowed.currency)
        return Wording(
            title: String(localized: "\(loan.name): installment in \(days) days", bundle: #bundle),
            body: String(localized: "Installment \(number) of \(loan.installmentCount) · \(amount)", bundle: #bundle),
        )
    }

    /// "Ana: due in 3 days" or "Ana: due today", and what is left in the debt's direction.
    func debtWording(_ debt: PersonalDebt, days: Int) -> Wording {
        let left = formatter.string(debt.remainingMoney)
        let body = switch debt.direction {
        case .theyOweMe: String(localized: "They owe you \(left).", bundle: #bundle)
        case .iOwe: String(localized: "You owe \(left).", bundle: #bundle)
        }
        return Wording(
            title: days == 0
                ? String(localized: "\(debt.person): due today", bundle: #bundle)
                : String(localized: "\(debt.person): due in \(days) days", bundle: #bundle),
            body: body,
        )
    }

    func cutoffWording(_ account: Account, in overview: HomeOverview) -> Wording {
        Wording(
            title: String(localized: "\(cardName(of: account, in: overview)): statement closes today", bundle: #bundle),
            body: String(localized: "From tomorrow, purchases go to next month's statement.", bundle: #bundle),
        )
    }

    func expiryWording(_ card: Card, in overview: HomeOverview) -> Wording {
        let name = CardDisplay.shortName(of: card)
        let services = overview.cardSubscriptions[card.id] ?? []
        return Wording(
            title: String(localized: "\(name) expires this month", bundle: #bundle),
            body: services.isEmpty
                ? String(localized: "Update it wherever it's saved before it stops working.", bundle: #bundle)
                : String(localized: "Update it in \(services.formatted(.list(type: .and))) before it stops working.", bundle: #bundle),
        )
    }

    func renewalWording(_ occurrence: RecurringOccurrence, display: TransactionDisplay) -> Wording {
        let rule = occurrence.rule
        return Wording(
            title: String(localized: "\(rule.name) renews tomorrow", bundle: #bundle),
            body: occurrenceBody(occurrence, display: display),
        )
    }

    func billWording(_ occurrence: RecurringOccurrence, display: TransactionDisplay) -> Wording {
        Wording(
            title: String(localized: "\(occurrence.rule.name) is due tomorrow", bundle: #bundle),
            body: occurrenceBody(occurrence, display: display),
        )
    }

    /// "US$15.00 on Visa ··1234": what a renewal or a bill charges, and where.
    private func occurrenceBody(_ occurrence: RecurringOccurrence, display: TransactionDisplay) -> String {
        let rule = occurrence.rule
        let amount = formatter.string(from: rule.amount, currencyCode: rule.currency)
        let method = display.methodName(of: RecurringSchedule.movement(
            from: rule,
            on: occurrence.date,
            exchangeRate: .single(rule.currency),
        ))
        return String(localized: "\(amount) on \(method)", bundle: #bundle)
    }

    func cardName(of account: Account, in overview: HomeOverview) -> String {
        let holder = overview.cards.first { $0.accountID == account.id && $0.kind == .creditHolder }
        return holder.map(CardDisplay.shortName(of:)) ?? CardDisplay.name(of: account)
    }
}
