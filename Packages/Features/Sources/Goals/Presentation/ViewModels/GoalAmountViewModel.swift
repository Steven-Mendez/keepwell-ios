import Core
import Domain
import Foundation
import GoalsDomain
import Observation

/// "Add money" or "Withdraw" for one goal. Only the goal's total changes; no account moves.
@MainActor
@Observable
public final class GoalAmountViewModel: Identifiable {
    public enum Action: Sendable {
        case add
        case withdraw
    }

    public let id = UUID()
    public let goal: SavingsGoal
    public let action: Action
    public var amountText = "" {
        didSet { failure = nil }
    }

    public private(set) var isSaving = false
    private var failure: String?
    private let moveMoney: any MoveSavingsGoalMoneyUseCase

    public init(goal: SavingsGoal, action: Action, moveMoney: any MoveSavingsGoalMoneyUseCase) {
        self.goal = goal
        self.action = action
        self.moveMoney = moveMoney
    }

    public var title: String {
        switch action {
        case .add: String(localized: "Add money", bundle: #bundle)
        case .withdraw: String(localized: "Withdraw", bundle: #bundle)
        }
    }

    var amount: Decimal? {
        AmountInput.decimal(from: amountText)
    }

    /// Withdrawing more than is set aside is pointed out while typing, before the button is tapped.
    public var errorMessage: String? {
        if action == .withdraw, let amount, amount > goal.saved {
            return String(localized: "You can't withdraw more than you've set aside.", bundle: #bundle)
        }
        return failure
    }

    public var canSave: Bool {
        guard let amount, amount > 0, !isSaving else { return false }
        return action == .add || amount <= goal.saved
    }

    /// Rewrites the typed amount with grouping and two decimals once the field loses focus.
    public func formatAmount() {
        if let formatted = AmountInput.formatted(amountText) {
            amountText = formatted
        }
    }

    /// Returns whether it was saved.
    public func save() async -> Bool {
        guard canSave, let amount else { return false }
        isSaving = true
        defer { isSaving = false }
        do {
            switch action {
            case .add: try await moveMoney.addMoney(id: goal.id, amount: amount)
            case .withdraw: try await moveMoney.withdraw(id: goal.id, amount: amount)
            }
            return true
        } catch {
            failure = String(localized: "We couldn't save the goal. Try again.", bundle: #bundle)
            return false
        }
    }
}
