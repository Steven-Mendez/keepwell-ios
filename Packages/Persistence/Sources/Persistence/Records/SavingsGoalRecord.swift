import Domain
import Foundation
import SwiftData

/// A savings goal. Every property is optional or defaulted and nothing is unique, as CloudKit
/// requires; amounts are exact decimal strings like every other amount in the store, and the
/// target month is two plain numbers because it has no day or time zone to store as a `Date`.
@Model
public final class SavingsGoalRecord: AuditedRecord {
    public var id = UUID()
    var name = ""
    var targetAmount = "0"
    var targetCurrency = ""
    var saved = "0"
    var targetMonth: Int?
    var targetYear: Int?
    var icon: String?
    var color: String?
    var createdAt = Date.now
    var updatedAt = Date.now
    var deletedAt: Date?

    init(id: UUID) {
        self.id = id
    }

    func update(from goal: SavingsGoal) {
        name = goal.name
        targetAmount = DecimalCoding.string(goal.target.amount)
        targetCurrency = goal.target.currency
        saved = DecimalCoding.string(goal.saved)
        targetMonth = goal.targetMonth?.month
        targetYear = goal.targetMonth?.year
        icon = goal.icon
        color = goal.color
    }

    func toDomain() throws(DomainCorruption) -> SavingsGoal {
        var month: TargetMonth?
        if let targetMonth, let targetYear {
            do {
                month = try TargetMonth(month: targetMonth, year: targetYear)
            } catch {
                throw DomainCorruption("Savings goal month \(targetMonth)/\(targetYear)")
            }
        }
        return try SavingsGoal(
            id: id,
            name: name,
            target: Money(DecimalCoding.decimal(targetAmount), targetCurrency),
            saved: DecimalCoding.decimal(saved),
            targetMonth: month,
            icon: icon,
            color: color,
        )
    }
}
