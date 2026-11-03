import Foundation

public struct TransactionCategory: Identifiable, Hashable, Sendable, Codable {
    /// A stable slug, separate from `name`, so renaming a category doesn't orphan its history.
    public let id: String
    public let name: String
    public let kind: TransactionKind

    public init(id: String, name: String, kind: TransactionKind) {
        self.id = id
        self.name = name
        self.kind = kind
    }
}

extension TransactionCategory {
    /// Initial set from HANDOFF → "Categorías". People can edit them later.
    public static let defaultExpense: [Self] = [
        ("groceries", "Supermercado"), ("restaurants", "Restaurantes"), ("transport", "Transporte"),
        ("housing", "Vivienda"), ("utilities", "Servicios"), ("health", "Salud"), ("education", "Educación"),
        ("leisure", "Ocio"), ("shopping", "Compras"), ("subscriptions", "Suscripciones"),
        ("personal-care", "Cuidado personal"), ("family", "Familia"), ("travel", "Viajes"),
        ("fees", "Comisiones"), ("tools", "Herramientas"), ("other-expense", "Otros"),
    ].map { Self(id: $0.0, name: $0.1, kind: .expense) }

    public static let defaultIncome: [Self] = [
        ("salary", "Salario"), ("extra", "Extra"), ("interest", "Intereses"),
        ("refunds", "Reembolsos"), ("other-income", "Otros ingresos"),
    ].map { Self(id: $0.0, name: $0.1, kind: .income) }

    public static var defaults: [Self] {
        defaultExpense + defaultIncome
    }

    /// Where reconciliation adjustments and uncategorized imports land.
    public static let otherExpenseID = "other-expense"
    public static let otherIncomeID = "other-income"
}
