import Domain
import Foundation
import SwiftData

// Wire rows → records: the silent write path of the sync engine. A row from the server is stored as
// the server's truth (ADR 0005 in keepwell-api), saved with plain `save()` so it is never queued back,
// and a local tombstone stays final. Payments and repayments, rows on the wire, are merged into the
// loan or debt that holds them on this iPhone.

struct WireReader {
    let row: [String: Any]

    func string(_ key: String) throws -> String {
        guard let value = row[key] as? String else { throw DomainCorruption("wire \(key)") }
        return value
    }

    func optionalString(_ key: String) -> String? {
        row[key] as? String
    }

    func int(_ key: String) throws -> Int {
        guard let value = row[key] as? Int else { throw DomainCorruption("wire \(key)") }
        return value
    }

    func optionalInt(_ key: String) -> Int? {
        row[key] as? Int
    }

    func bool(_ key: String) -> Bool {
        row[key] as? Bool ?? false
    }

    func uuid(_ key: String) throws -> UUID {
        guard let value = try UUID(uuidString: string(key)) else { throw DomainCorruption("wire \(key)") }
        return value
    }

    func optionalUUID(_ key: String) -> UUID? {
        optionalString(key).flatMap(UUID.init(uuidString:))
    }

    func date(_ key: String) throws -> Date {
        guard let value = try Self.parse(string(key)) else { throw DomainCorruption("wire \(key)") }
        return value
    }

    func optionalDate(_ key: String) -> Date? {
        optionalString(key).flatMap(Self.parse)
    }

    func strings(_ key: String) -> [String] {
        row[key] as? [String] ?? []
    }

    static func parse(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }

    func audit(_ record: some AuditedRecord) throws {
        try record.apply(RecordMetadata(
            createdAt: date("created_at"),
            updatedAt: date("updated_at"),
            deletedAt: optionalDate("deleted_at"),
        ))
    }
}

extension SwiftDataStore {
    @discardableResult
    public func applyRemote(entity: String, row data: Data) throws(DomainError) -> Bool {
        try perform { context in
            guard let row = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
            let wire = WireReader(row: row)
            let applied = try apply(entity: entity, wire, in: context)
            if applied {
                try context.save()
            }
            return applied
        }
    }

    public func adoptUpdatedAt(entity: String, entityID: String, updatedAt: Date) throws(DomainError) {
        try perform { context in
            guard let record = try auditedRecord(entity: entity, id: entityID, in: context), record.deletedAt == nil else { return }
            record.updatedAt = updatedAt
            try context.save()
        }
    }

    private func fetch<T: PersistentModel>(_ type: T.Type, _ predicate: Predicate<T>, in context: ModelContext) throws -> T? {
        try context.fetch(FetchDescriptor(predicate: predicate)).first
    }

    private func auditedRecord(entity: String, id: String, in context: ModelContext) throws -> (any AuditedRecord)? {
        guard let uuid = UUID(uuidString: id) else {
            return switch entity {
            case "category": try fetch(CategoryRecord.self, #Predicate { $0.id == id }, in: context)
            case "notificationState": try fetch(NotificationStateRecord.self, #Predicate { $0.id == id }, in: context)
            default: nil
            }
        }
        return switch entity {
        case "account": try fetch(AccountRecord.self, #Predicate { $0.id == uuid }, in: context)
        case "card": try fetch(CardRecord.self, #Predicate { $0.id == uuid }, in: context)
        case "transaction": try fetch(TransactionRecord.self, #Predicate { $0.id == uuid }, in: context)
        case "recurringRule": try fetch(RecurringRuleRecord.self, #Predicate { $0.id == uuid }, in: context)
        case "savingsGoal": try fetch(SavingsGoalRecord.self, #Predicate { $0.id == uuid }, in: context)
        case "loan": try fetch(LoanRecord.self, #Predicate { $0.id == uuid }, in: context)
        case "personalDebt": try fetch(PersonalDebtRecord.self, #Predicate { $0.id == uuid }, in: context)
        case "categorizationRule": try fetch(CategorizationRuleRecord.self, #Predicate { $0.id == uuid }, in: context)
        default: nil
        }
    }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    func apply(entity: String, _ wire: WireReader, in context: ModelContext) throws -> Bool {
        switch entity {
        case "account":
            let id = try wire.uuid("id")
            let record = try fetch(AccountRecord.self, #Predicate { $0.id == id }, in: context)
            if record?.deletedAt != nil {
                return false
            }
            let account = record ?? AccountRecord(id: id).inserted(into: context)
            account.name = try wire.string("name")
            account.bank = wire.optionalString("bank")
            account.kindRaw = try wire.string("kind")
            let balances = (wire.row["opening_balances"] as? [[String: String]] ?? []).compactMap { item -> Money? in
                guard let amount = item["amount"].flatMap({ Decimal(string: $0) }), let currency = item["currency"] else { return nil }
                return Money(amount, currency)
            }
            account.openingBalances = MoneyListCoding.string(balances)
            account.openingDate = try wire.date("opening_date")
            account.debtModeRaw = wire.optionalString("debt_mode")
            account.limitAmount = wire.optionalString("limit_amount")
            account.limitCurrency = wire.optionalString("limit_currency")
            account.cutoffDay = wire.optionalInt("cutoff_day")
            account.dueDay = wire.optionalInt("due_day")
            // A row without the key comes from an app older than the column: the account stays as it was.
            if wire.row.keys.contains("closed_at") {
                account.closedAt = wire.optionalDate("closed_at")
            }
            try wire.audit(account)
        case "card":
            let id = try wire.uuid("id")
            let record = try fetch(CardRecord.self, #Predicate { $0.id == id }, in: context)
            if record?.deletedAt != nil {
                return false
            }
            let card = record ?? CardRecord(id: id).inserted(into: context)
            card.accountID = try wire.uuid("account_id")
            card.kindRaw = try wire.string("kind")
            card.networkRaw = wire.optionalString("network")
            card.lastFour = wire.optionalString("last_four")
            card.colorRaw = wire.optionalString("color")
            card.productName = wire.optionalString("product_name")
            card.expiryMonth = wire.optionalInt("expiry_month")
            card.expiryYear = wire.optionalInt("expiry_year")
            try wire.audit(card)
        case "category":
            let id = try wire.string("id")
            let record = try fetch(CategoryRecord.self, #Predicate { $0.id == id }, in: context)
            if record?.deletedAt != nil {
                return false
            }
            let category = record ?? CategoryRecord(id: id).inserted(into: context)
            category.name = try wire.string("name")
            category.kindRaw = try wire.string("kind")
            category.icon = wire.optionalString("icon")
            category.color = wire.optionalString("color")
            category.isRenamed = wire.bool("is_renamed")
            category.sortIndex = try wire.int("sort_index")
            category.budgetAmount = wire.optionalString("budget_amount")
            category.budgetCurrency = wire.optionalString("budget_currency")
            try wire.audit(category)
            category.isRemoved = category.deletedAt != nil
        case "transaction":
            let id = try wire.uuid("id")
            let record = try fetch(TransactionRecord.self, #Predicate { $0.id == id }, in: context)
            if record?.deletedAt != nil {
                return false
            }
            let transaction = record ?? TransactionRecord(id: id).inserted(into: context)
            transaction.date = try wire.date("date")
            transaction.statusRaw = try wire.string("status")
            transaction.descriptionText = try wire.string("description")
            transaction.kindRaw = try wire.string("kind")
            transaction.categoryID = wire.optionalString("category_id")
            transaction.amount = try wire.string("amount")
            transaction.currency = try wire.string("currency")
            transaction.accountID = try wire.uuid("account_id")
            transaction.cardID = wire.optionalUUID("card_id")
            transaction.destinationAccountID = wire.optionalUUID("destination_account_id")
            transaction.actualDebitedPrincipal = wire.optionalString("actual_debited_principal")
            transaction.ratePrincipal = try wire.string("rate_principal")
            transaction.rateSecond = try wire.string("rate_second")
            transaction.rate = try wire.string("rate")
            transaction.isShared = wire.bool("is_shared")
            transaction.note = wire.optionalString("note")
            transaction.recurringID = wire.optionalUUID("recurring_id")
            transaction.tagsText = TagsText.encode(wire.strings("tags"))
            transaction.sourceRaw = wire.optionalString("source") ?? transaction.sourceRaw
            try wire.audit(transaction)
        case "recurringRule":
            let id = try wire.uuid("id")
            let record = try fetch(RecurringRuleRecord.self, #Predicate { $0.id == id }, in: context)
            if record?.deletedAt != nil {
                return false
            }
            let rule = record ?? RecurringRuleRecord(id: id).inserted(into: context)
            rule.name = try wire.string("name")
            rule.kindRaw = try wire.string("kind")
            rule.categoryID = wire.optionalString("category_id")
            rule.amount = try wire.string("amount")
            rule.currency = try wire.string("currency")
            rule.accountID = try wire.uuid("account_id")
            rule.cardID = wire.optionalUUID("card_id")
            rule.destinationAccountID = wire.optionalUUID("destination_account_id")
            rule.frequencyRaw = try wire.string("frequency")
            rule.interval = try wire.int("interval")
            rule.startDate = try wire.date("start_date")
            rule.nextDate = try wire.date("next_date")
            rule.endDate = wire.optionalDate("end_date")
            rule.isSubscription = wire.bool("is_subscription")
            rule.autoConfirm = wire.bool("auto_confirm")
            rule.isPaused = wire.bool("is_paused")
            rule.note = wire.optionalString("note")
            rule.tagsText = TagsText.encode(wire.strings("tags"))
            rule.sourceRaw = wire.optionalString("source") ?? rule.sourceRaw
            try wire.audit(rule)
        case "savingsGoal":
            let id = try wire.uuid("id")
            let record = try fetch(SavingsGoalRecord.self, #Predicate { $0.id == id }, in: context)
            if record?.deletedAt != nil {
                return false
            }
            let goal = record ?? SavingsGoalRecord(id: id).inserted(into: context)
            goal.name = try wire.string("name")
            goal.targetAmount = try wire.string("target_amount")
            goal.targetCurrency = try wire.string("target_currency")
            goal.saved = try wire.string("saved")
            goal.targetMonth = wire.optionalInt("target_month")
            goal.targetYear = wire.optionalInt("target_year")
            goal.icon = wire.optionalString("icon")
            goal.color = wire.optionalString("color")
            try wire.audit(goal)
        case "loan":
            let id = try wire.uuid("id")
            let record = try fetch(LoanRecord.self, #Predicate { $0.id == id }, in: context)
            if record?.deletedAt != nil {
                return false
            }
            let loan = record ?? LoanRecord(id: id).inserted(into: context)
            loan.name = try wire.string("name")
            loan.lender = wire.optionalString("lender")
            loan.borrowedAmount = try wire.string("borrowed_amount")
            loan.borrowedCurrency = try wire.string("borrowed_currency")
            loan.installmentAmount = try wire.string("installment_amount")
            loan.installmentCount = try wire.int("installment_count")
            loan.frequencyRaw = try wire.string("frequency")
            loan.firstDueDate = try wire.date("first_due_date")
            try wire.audit(loan)
        case "loanPayment":
            let loanID = try wire.uuid("loan_id")
            // A payment can arrive before its loan; the loan's row will bring it in on its own pull.
            guard let loan = try fetch(LoanRecord.self, #Predicate { $0.id == loanID }, in: context),
                  loan.deletedAt == nil else { return false }
            var payments = try loan.toDomain().payments
            let number = try wire.int("number")
            payments.removeAll { $0.number == number }
            if wire.optionalString("deleted_at") == nil {
                try payments.append(LoanPayment(
                    number: number,
                    paidAt: wire.date("paid_at"),
                    transactionID: wire.optionalUUID("transaction_id"),
                ))
            }
            loan.setPayments(payments.sorted { $0.number < $1.number })
        case "personalDebt":
            let id = try wire.uuid("id")
            let record = try fetch(PersonalDebtRecord.self, #Predicate { $0.id == id }, in: context)
            if record?.deletedAt != nil {
                return false
            }
            let debt = record ?? PersonalDebtRecord(id: id).inserted(into: context)
            debt.person = try wire.string("person")
            debt.directionRaw = try wire.string("direction")
            debt.amount = try wire.string("amount")
            debt.currency = try wire.string("currency")
            debt.date = try wire.date("date")
            debt.note = wire.optionalString("note")
            debt.settledAt = wire.optionalDate("settled_at")
            debt.transactionID = wire.optionalUUID("transaction_id")
            // A row without the key comes from an app older than the column: the date stays as it was.
            if wire.row.keys.contains("due_date") {
                debt.dueDate = wire.optionalDate("due_date")
            }
            try wire.audit(debt)
        case "personalDebtRepayment":
            let debtID = try wire.uuid("debt_id")
            guard let debt = try fetch(PersonalDebtRecord.self, #Predicate { $0.id == debtID }, in: context),
                  debt.deletedAt == nil else { return false }
            let id = try wire.uuid("id")
            var repayments = try debt.toDomain().repayments.filter { $0.id != id }
            if wire.optionalString("deleted_at") == nil {
                guard let amount = try Decimal(string: wire.string("amount")) else { throw DomainCorruption("wire amount") }
                try repayments.append(DebtRepayment(id: id, amount: amount, date: wire.date("date")))
            }
            debt.setRepayments(repayments.sorted { $0.date < $1.date })
        case "categorizationRule":
            let id = try wire.uuid("id")
            let record = try fetch(CategorizationRuleRecord.self, #Predicate { $0.id == id }, in: context)
            if record?.deletedAt != nil {
                return false
            }
            let rule = record ?? CategorizationRuleRecord(id: id).inserted(into: context)
            rule.match = try wire.string("match")
            rule.categoryID = try wire.string("category_id")
            rule.kindRaw = try wire.string("kind")
            rule.tagsText = TagsText.encode(wire.strings("tags"))
            rule.sortIndex = try wire.int("sort_index")
            try wire.audit(rule)
        case "notificationState":
            let id = try wire.string("id")
            let record = try fetch(NotificationStateRecord.self, #Predicate { $0.id == id }, in: context)
            // A tombstone is final: the id is long past and won't be computed again.
            if record?.deletedAt != nil {
                return false
            }
            let state = record ?? NotificationStateRecord(id: id).inserted(into: context)
            state.readAt = wire.optionalDate("read_at")
            state.dismissedAt = wire.optionalDate("dismissed_at")
            try wire.audit(state)
        case "settings":
            let settings = try context.fetch(FetchDescriptor<SettingsRecord>()).first ?? SettingsRecord().inserted(into: context)
            // Only the synced columns; unlock, relock, hiding amounts and the iCloud switch stay this iPhone's.
            settings.principal = try wire.string("principal")
            settings.second = wire.optionalString("second")
            settings.rate = try wire.string("rate")
            settings.paymentReminderDaysBefore = try wire.int("payment_reminder_days_before")
            settings.hasCompletedOnboarding = wire.bool("has_completed_onboarding")
            // A row without the key comes from an app older than the column: it says nothing about it.
            if wire.row.keys.contains("time_zone") {
                settings.timeZone = wire.optionalString("time_zone")
            }
            settings.updatedAt = try wire.date("updated_at")
        default:
            return false
        }
        return true
    }
}
