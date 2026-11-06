import Foundation

/// A savings goal in the backup file (schema 3). `saved` is in the target's currency, which is why
/// it is a bare decimal string and not a money object.
public struct SavingsGoalBackup: Codable, Sendable, Equatable {
    public struct Month: Codable, Sendable, Equatable {
        public let month: Int
        public let year: Int
    }

    public let id: String
    public let name: String
    public let target: MoneyBackup
    public let saved: String
    public let targetMonth: Month?
    public let icon: String?
    public let color: String?
    public let createdAt: Date
    public let updatedAt: Date
    public let deletedAt: Date?

    init(_ stamped: Stamped<SavingsGoal>) {
        let goal = stamped.value
        id = PortableID.string(goal.id)
        name = goal.name
        target = MoneyBackup(goal.target)
        saved = PortableDecimal.string(goal.saved)
        targetMonth = goal.targetMonth.map { Month(month: $0.month, year: $0.year) }
        icon = goal.icon
        color = goal.color
        createdAt = stamped.metadata.createdAt
        updatedAt = stamped.metadata.updatedAt
        deletedAt = stamped.metadata.deletedAt
    }

    /// The amounts are checked as saving checks them; the currency isn't held to the settings,
    /// since a goal keeps the currency it was created in after the person changes theirs.
    func toDomain() throws(DomainError) -> Stamped<SavingsGoal> {
        let goal = try SavingsGoal(
            id: PortableID.uuid(id),
            name: name,
            target: target.toDomain(),
            saved: PortableDecimal.decimal(saved),
            targetMonth: targetMonth.map { month throws(DomainError) in try TargetMonth(month: month.month, year: month.year) },
            icon: icon,
            color: color,
        )
        try goal.checkAmounts()
        return Stamped(goal, RecordMetadata(createdAt: createdAt, updatedAt: updatedAt, deletedAt: deletedAt))
    }
}
