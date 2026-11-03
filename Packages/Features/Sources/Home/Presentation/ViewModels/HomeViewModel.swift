import Core
import Domain
import Foundation
import HomeDomain
import Observation
import SharedPresentation

@MainActor
@Observable
public final class HomeViewModel {
    public enum State: Equatable {
        case loading
        case loaded(HomeOverview)
        case failed
    }

    public private(set) var state = State.loading
    /// Planned movements being confirmed, so their button can't be tapped twice.
    public private(set) var confirming: Set<UUID> = []
    public private(set) var actionError: String?

    private let getOverview: any GetHomeOverviewUseCase
    private let confirmPlanned: any ConfirmPlannedTransactionUseCase
    private let calendar: Calendar
    let formatter = CurrencyFormatter()

    public init(
        getOverview: any GetHomeOverviewUseCase,
        confirmPlanned: any ConfirmPlannedTransactionUseCase,
        calendar: Calendar = .current,
    ) {
        self.getOverview = getOverview
        self.confirmPlanned = confirmPlanned
        self.calendar = calendar
    }

    public var overview: HomeOverview? {
        if case let .loaded(overview) = state {
            overview
        } else {
            nil
        }
    }

    public func load() async {
        do {
            state = try await .loaded(getOverview.execute())
        } catch {
            state = .failed
        }
    }

    public func confirm(_ id: UUID) async {
        guard !confirming.contains(id) else { return }
        confirming.insert(id)
        defer { confirming.remove(id) }
        do {
            try await confirmPlanned.execute(id: id)
            actionError = nil
            await load()
        } catch {
            actionError = String(localized: "We couldn't confirm it. Try again.", bundle: #bundle)
        }
    }

    // MARK: - Display

    var display: TransactionDisplay? {
        overview.map { TransactionDisplay(accounts: $0.accounts, cards: $0.cards, categories: $0.categories) }
    }

    /// The whole part and the cents, drawn at two sizes ("$11,157" ".46").
    func netWorthParts(_ overview: HomeOverview) -> (whole: String, cents: String) {
        let text = formatter.string(overview.netWorth)
        guard let dot = text.lastIndex(of: ".") else { return (text, "") }
        return (String(text[..<dot]), String(text[dot...]))
    }

    /// "≈ C$408,634 · rate 36.6243".
    func secondCurrencyLine(_ overview: HomeOverview) -> String? {
        guard let second = overview.netWorthInSecond else { return nil }
        let amount = formatter.string(second, fractionDigits: 0)
        let rate = formatter.number(overview.settings.rate, fractionDigits: 4)
        return String(localized: "≈ \(amount) · rate \(rate)", bundle: #bundle)
    }

    func countsLine(_ overview: HomeOverview) -> String {
        // Two strings so each number gets its own plural form.
        let accounts = overview.accountCount
        let cards = overview.cardCount
        return String(localized: "\(accounts) accounts", bundle: #bundle) + " · " + String(localized: "\(cards) cards", bundle: #bundle)
    }

    /// The month's name as the person's locale writes it standing alone ("October").
    func monthName(_ month: YearMonth) -> String {
        guard let start = month.dateInterval(in: calendar)?.start else { return month.description }
        return start.formatted(.dateTime.month(.wide))
    }

    func spentTitle(_ overview: HomeOverview) -> String {
        let month = monthName(overview.month.month)
        return String(localized: "Spent in \(month)", bundle: #bundle)
    }

    func savedBadge(_ overview: HomeOverview) -> String? {
        guard let rate = overview.month.savingsRate, rate > 0 else { return nil }
        let percent = formatter.number(rate * 100, fractionDigits: 0)
        return String(localized: "\(percent)% saved", bundle: #bundle)
    }

    func money(_ amount: Decimal, _ overview: HomeOverview) -> String {
        formatter.string(from: amount, currencyCode: overview.settings.principal)
    }

    /// "They don't count toward balances until you confirm them · C$7,500 (≈ $204.78)".
    func plannedCaption(_ overview: HomeOverview) -> String {
        let summary = overview.plannedSummary
        let principal = formatter.string(from: summary.principalTotal, currencyCode: overview.settings.principal)
        let total = if let second = overview.settings.second {
            "\(formatter.string(from: summary.secondTotal, currencyCode: second, fractionDigits: 0)) (≈ \(principal))"
        } else {
            principal
        }
        return String(localized: "They don't count toward balances until you confirm them · \(total)", bundle: #bundle)
    }

    func plannedTitle(_ overview: HomeOverview) -> String {
        let count = overview.plannedSummary.count
        return String(localized: "Planned · \(count)", bundle: #bundle)
    }

    /// "Mastercard ··6158 · additional Family".
    func additionalTitle(_ status: HomeOverview.AdditionalCardStatus) -> String {
        let card = status.holder.map(CardDisplay.shortName(of:)) ?? CardDisplay.name(of: status.account)
        let holder = status.card.additional?.holderName ?? ""
        return String(localized: "\(card) · additional \(holder)", bundle: #bundle)
    }

    /// "C$2,150 of C$4,000 cap this cycle".
    func additionalCaption(_ status: HomeOverview.AdditionalCardStatus) -> String {
        let spent = formatter.string(status.usage.spent, fractionDigits: 0)
        guard let cap = status.usage.cap else { return spent }
        let capText = formatter.string(cap, fractionDigits: 0)
        return String(localized: "\(spent) of \(capText) cap this cycle", bundle: #bundle)
    }
}
