import Core
import Domain
import Foundation
import Observation
import RecurringDomain
import SharedPresentation

/// Drives "Link to a recurring", opened from a movement: the rules it could be a payment of, the
/// likeliest first. Choosing one links the movement; the rule's schedule doesn't move.
@MainActor
@Observable
public final class RecurringRulePickerViewModel: Identifiable {
    public enum State: Equatable {
        case loading
        case loaded(RecurringOverview)
        case failed
    }

    public let transaction: Domain.Transaction
    public private(set) var state = State.loading
    public private(set) var isWorking = false
    public private(set) var actionError: String?
    public nonisolated var id: UUID { transaction.id }

    private let getOverview: any GetRecurringOverviewUseCase
    private let linkPayment: any LinkRecurringPaymentUseCase
    private let formatter = CurrencyFormatter()

    public init(
        transaction: Domain.Transaction,
        getOverview: any GetRecurringOverviewUseCase,
        linkPayment: any LinkRecurringPaymentUseCase,
    ) {
        self.transaction = transaction
        self.getOverview = getOverview
        self.linkPayment = linkPayment
    }

    public func load() async {
        do {
            state = try await .loaded(getOverview.execute())
        } catch {
            state = .failed
        }
    }

    public var overview: RecurringOverview? {
        if case let .loaded(overview) = state {
            overview
        } else {
            nil
        }
    }

    /// Rules of the movement's kind: those it would be suggested for first (same currency, and its
    /// amount or name matches), then the rest of its currency, then any other, by name.
    public var rules: [RecurringRule] {
        guard let overview else { return [] }
        let suggested = Set(overview.rules.filter { !RecurringStatus.paymentCandidates(for: $0, in: [transaction]).isEmpty }.map(\.id))
        return overview.rules
            .filter { RecurringStatus.canLink(transaction, to: $0) }
            .sorted { lhs, rhs in
                let left = (suggested.contains(lhs.id) ? 0 : 1, lhs.currency == transaction.currency ? 0 : 1)
                let right = (suggested.contains(rhs.id) ? 0 : 1, rhs.currency == transaction.currency ? 0 : 1)
                if left != right {
                    return left < right
                }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }

    public func category(of rule: RecurringRule) -> TransactionCategory? {
        overview?.categories.first { $0.id == rule.categoryID }
    }

    /// "$15.99 · Every month".
    public func subtitle(of rule: RecurringRule) -> String {
        "\(formatter.string(from: rule.amount, currencyCode: rule.currency)) · \(RecurringDisplay.frequency(of: rule))"
    }

    /// Links the movement to the rule; `true` once saved.
    public func link(to rule: RecurringRule) async -> Bool {
        guard !isWorking else { return false }
        isWorking = true
        defer { isWorking = false }
        do {
            try await linkPayment.execute(transactionID: transaction.id, ruleID: rule.id)
            actionError = nil
            return true
        } catch {
            actionError = String(localized: "We couldn't link it. Try again.", bundle: #bundle)
            return false
        }
    }
}
