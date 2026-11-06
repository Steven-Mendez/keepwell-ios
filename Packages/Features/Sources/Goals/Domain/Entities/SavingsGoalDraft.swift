import Domain
import Foundation

/// A goal as the editor builds it. `id` is `nil` for a new goal. What is set aside is never part
/// of it: "Add money" and "Withdraw" change that, so editing can't overwrite it.
public struct SavingsGoalDraft: Hashable, Sendable {
    public var id: UUID?
    public var name: String
    /// When editing, only the amount is used: a goal keeps the currency it was created in.
    public var target: Money
    public var targetMonth: TargetMonth?
    public var icon: String?
    public var color: String?

    public init(
        id: UUID? = nil,
        name: String,
        target: Money,
        targetMonth: TargetMonth? = nil,
        icon: String? = nil,
        color: String? = nil,
    ) {
        self.id = id
        self.name = name
        self.target = target
        self.targetMonth = targetMonth
        self.icon = icon
        self.color = color
    }
}
