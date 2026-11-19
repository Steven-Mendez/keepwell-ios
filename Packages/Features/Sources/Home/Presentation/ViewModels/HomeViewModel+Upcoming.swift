import Domain
import Foundation
import HomeDomain
import SharedPresentation

/// Home's "Upcoming" card: everything overdue, then the next few things due this week, from the
/// same list as the status line (`HomeOverview.upcomingPayments`).
extension HomeViewModel {
    /// Rows after the overdue ones: nothing late is ever hidden, so the card and the status line agree.
    static let upcomingCount = 3

    /// Everything overdue, oldest first, then up to three for today and the coming days.
    func upcomingRows(_ overview: HomeOverview) -> [UpcomingPayment] {
        let overdue = overview.upcomingPayments.filter { $0.status == .overdue }
        let next = overview.upcomingPayments.filter { $0.status != .overdue }.prefix(Self.upcomingCount)
        return overdue + next
    }

    /// "See all" goes where most of the rows can be acted on: the drafts when there are any.
    func upcomingListsDrafts(_ rows: [UpcomingPayment]) -> Bool {
        rows.contains {
            if case .draft = $0.kind {
                true
            } else {
                false
            }
        }
    }

    func upcomingTitle(_ payment: UpcomingPayment) -> String {
        switch payment.kind {
        case let .draft(transaction): transaction.description
        case let .recurring(rule): rule.name
        case let .card(accountID, _): overview?.accounts.first { $0.id == accountID }.map(CardDisplay.name(of:)) ?? ""
        case let .installment(loanID, _, _): overview?.loans.first { $0.loan.id == loanID }?.loan.name ?? ""
        case let .debt(_, person, _): person
        }
    }

    /// When, in words ("Overdue · 3 days", "Tomorrow", "Oct 30"), then what it is.
    func upcomingSubtitle(_ payment: UpcomingPayment, now: Date = .now) -> String {
        [upcomingWhen(payment, now: now), upcomingDetail(payment)].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    func upcomingWhen(_ payment: UpcomingPayment, now: Date = .now) -> String {
        guard payment.status != .overdue else {
            return String(localized: "Overdue · \(-payment.daysFromToday) days", bundle: #bundle)
        }
        return RecurringDisplay.day(payment.date, today: now, calendar: calendar)
    }

    private func upcomingDetail(_ payment: UpcomingPayment) -> String {
        switch payment.kind {
        case let .draft(transaction):
            display?.subtitle(of: transaction) ?? ""
        case let .recurring(rule):
            display?.subtitle(of: movement(of: rule, on: payment.date)) ?? ""
        case .card:
            String(localized: "Card payment", bundle: #bundle)
        case let .installment(_, number, count):
            String(localized: "Installment \(number) of \(count)", bundle: #bundle)
        case .debt:
            ""
        }
    }

    func upcomingAmount(_ payment: UpcomingPayment, hidden: Bool) -> String {
        let text = switch payment.kind {
        case let .draft(transaction): display?.amount(of: transaction) ?? ""
        case let .recurring(rule): display?.amount(of: movement(of: rule, on: payment.date)) ?? ""
        case .card, .installment, .debt: formatter.string(payment.amount)
        }
        return visible(text, hidden: hidden)
    }

    /// A rule's category, whose color tints a brand's monogram.
    /// A recurring payment's logo: its rule's merchant's first, then the brand the rule's name names.
    func upcomingLogo(_ payment: UpcomingPayment) -> LogoSubject? {
        guard case let .recurring(rule) = payment.kind else { return nil }
        return MerchantLogos.logo(of: rule, merchants: overview?.merchants ?? [])
    }

    func upcomingCategory(_ payment: UpcomingPayment) -> TransactionCategory? {
        guard case let .recurring(rule) = payment.kind else { return nil }
        return rule.categoryID.flatMap { id in overview?.categories.first { $0.id == id } }
    }

    private func movement(of rule: RecurringRule, on date: Date) -> Transaction {
        RecurringSchedule.movement(from: rule, on: date, exchangeRate: .single(rule.currency))
    }
}
