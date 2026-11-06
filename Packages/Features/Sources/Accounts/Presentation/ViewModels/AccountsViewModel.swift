import AccountsDomain
import Core
import Domain
import Foundation
import Observation

/// One card in the wallet: a credit card, a bank account's debit card or cash, which the person
/// also carries and reads as one more card.
public enum WalletCard: Identifiable, Hashable, Sendable {
    case credit(AccountsOverview.CreditCard)
    case debit(AccountsOverview.Deposit)
    case cash(AccountsOverview.Cash)

    public var id: UUID {
        switch self {
        case let .credit(card): card.id
        case let .debit(deposit): deposit.id
        case let .cash(cash): cash.id
        }
    }

    var kind: AccountsViewModel.WalletFilter {
        switch self {
        case .credit: .credit
        case .debit: .debit
        case .cash: .cash
        }
    }
}

@MainActor
@Observable
public final class AccountsViewModel {
    public enum State: Equatable {
        case loading
        case loaded(AccountsOverview)
        case failed
    }

    /// The chips over the wallet; `all` shows every card.
    public enum WalletFilter: Hashable, Sendable, CaseIterable {
        case all
        case debit
        case credit
        case cash
    }

    public private(set) var state = State.loading
    /// The person's own name, printed on their main cards.
    public private(set) var ownerName: String?
    public var filter = WalletFilter.all

    private let getOverview: any GetAccountsOverviewUseCase
    private let getPreferredName: any GetPreferredNameUseCase

    public init(getOverview: any GetAccountsOverviewUseCase, getPreferredName: any GetPreferredNameUseCase) {
        self.getPreferredName = getPreferredName
        self.getOverview = getOverview
    }

    public var overview: AccountsOverview? {
        if case let .loaded(overview) = state {
            overview
        } else {
            nil
        }
    }

    public func load() async {
        ownerName = await getPreferredName.execute()
        do {
            state = try await .loaded(getOverview.execute())
        } catch {
            state = .failed
        }
    }

    /// Every card back to front: debit, then credit, then cash in front, where the hand reaches it.
    var allCards: [WalletCard] {
        guard let overview else { return [] }
        return overview.deposits.map(WalletCard.debit) + overview.creditCards.map(WalletCard.credit) + overview.cash.map(WalletCard.cash)
    }

    /// The cards the chosen chip shows.
    var cards: [WalletCard] {
        filter == .all ? allCards : allCards.filter { $0.kind == filter }
    }

    /// Only the kinds the person has, so there's never a chip that empties the wallet. No chips at
    /// all with a single kind.
    var filters: [WalletFilter] {
        let kinds = WalletFilter.allCases.filter { kind in allCards.contains { $0.kind == kind } }
        return kinds.count > 1 ? [.all] + kinds : []
    }

    func title(of filter: WalletFilter) -> String {
        switch filter {
        case .all: String(localized: "All", bundle: #bundle)
        case .debit: String(localized: "Debit", bundle: #bundle)
        case .credit: String(localized: "Credit", bundle: #bundle)
        case .cash: String(localized: "Cash", bundle: #bundle)
        }
    }
}
