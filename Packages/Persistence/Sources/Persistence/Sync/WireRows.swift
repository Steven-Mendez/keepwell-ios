import Domain
import Foundation

// Records → wire rows: snake_case, exactly the columns of keepwell-web's `schema/sync.ts`
// (`wire-columns.json` in the shared fixtures), with `null` written out for absent values. Ids are
// lowercase and instants are `toISOString()` text, so the API stores them byte for byte.

typealias WireRow = [String: Any]

/// A record that syncs: its entity name in the protocol and its row.
protocol SyncableRecord: AuditedRecord {
    static var syncEntity: String { get }
    var syncID: String { get }
    func wireRow() throws -> WireRow
}

enum Wire {
    static func id(_ id: UUID) -> String {
        id.uuidString.lowercased()
    }

    static func id(_ id: UUID?) -> Any {
        id.map { $0.uuidString.lowercased() } ?? NSNull()
    }

    static func date(_ date: Date) -> String {
        NameBasedID.isoMilliseconds(date)
    }

    static func date(_ date: Date?) -> Any {
        date.map(NameBasedID.isoMilliseconds) ?? NSNull()
    }

    static func value(_ value: Any?) -> Any {
        value ?? NSNull()
    }

    static func audit(_ record: some AuditedRecord) -> WireRow {
        ["created_at": date(record.createdAt), "updated_at": date(record.updatedAt), "deleted_at": date(record.deletedAt)]
    }

    static func json(_ row: WireRow) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]),
              let text = String(bytes: data, encoding: .utf8)
        else { return "{}" }
        return text
    }
}

extension AccountRecord: SyncableRecord {
    static var syncEntity: String { "account" }
    var syncID: String { Wire.id(id) }

    func wireRow() throws -> WireRow {
        let balances = try MoneyListCoding.list(openingBalances)
            .map { ["amount": DecimalCoding.string($0.amount), "currency": $0.currency] }
        return Wire.audit(self).merging([
            "id": Wire.id(id), "name": name, "bank": Wire.value(bank), "kind": kindRaw, "opening_balances": balances,
            "opening_date": Wire.date(openingDate), "debt_mode": Wire.value(debtModeRaw), "limit_amount": Wire.value(limitAmount),
            "limit_currency": Wire.value(limitCurrency), "cutoff_day": Wire.value(cutoffDay), "due_day": Wire.value(dueDay),
            // Always sent, null while open: reopening has to clear it on the other devices.
            "closed_at": Wire.date(closedAt),
        ]) { $1 }
    }
}

extension CardRecord: SyncableRecord {
    static var syncEntity: String { "card" }
    var syncID: String { Wire.id(id) }

    func wireRow() throws -> WireRow {
        Wire.audit(self).merging([
            "id": Wire.id(id), "account_id": Wire.id(accountID), "kind": kindRaw, "network": Wire.value(networkRaw),
            "last_four": Wire.value(lastFour), "color": Wire.value(colorRaw), "product_name": Wire.value(productName),
            "expiry_month": Wire.value(expiryMonth), "expiry_year": Wire.value(expiryYear),
        ]) { $1 }
    }
}

extension CategoryRecord: SyncableRecord {
    static var syncEntity: String { "category" }
    var syncID: String { id }

    func wireRow() throws -> WireRow {
        var audit = Wire.audit(self)
        // A removed default is a tombstone on the wire, like a deleted custom category.
        if deletedAt == nil, isRemoved {
            audit["deleted_at"] = Wire.date(updatedAt)
        }
        return audit.merging([
            "id": id, "name": name, "kind": kindRaw, "icon": Wire.value(icon), "color": Wire.value(color), "is_renamed": isRenamed,
            "sort_index": sortIndex, "budget_amount": Wire.value(budgetAmount), "budget_currency": Wire.value(budgetCurrency),
        ]) { $1 }
    }
}

extension TransactionRecord: SyncableRecord {
    static var syncEntity: String { "transaction" }
    var syncID: String { Wire.id(id) }

    func wireRow() throws -> WireRow {
        Wire.audit(self).merging([
            "id": Wire.id(id), "date": Wire.date(date), "status": statusRaw, "description": descriptionText, "kind": kindRaw,
            "category_id": Wire.value(categoryID), "amount": amount, "currency": currency, "account_id": Wire.id(accountID),
            "card_id": Wire.id(cardID), "destination_account_id": Wire.id(destinationAccountID),
            "actual_debited_principal": Wire.value(actualDebitedPrincipal), "rate_principal": ratePrincipal, "rate_second": rateSecond,
            "rate": rate, "is_shared": isShared, "note": Wire.value(note), "recurring_id": Wire.id(recurringID),
            "tags": TagsText.decode(tagsText), "source": sourceRaw ?? RecordSource.app.rawValue,
            // Always sent, null for none: removing one has to clear it on the other devices.
            "merchant_id": Wire.id(merchantID), "via_merchant_id": Wire.id(viaMerchantID),
        ]) { $1 }
    }
}

extension RecurringRuleRecord: SyncableRecord {
    static var syncEntity: String { "recurringRule" }
    var syncID: String { Wire.id(id) }

    func wireRow() throws -> WireRow {
        Wire.audit(self).merging([
            "id": Wire.id(id), "name": name, "kind": kindRaw, "category_id": Wire.value(categoryID), "amount": amount,
            "currency": currency, "account_id": Wire.id(accountID), "card_id": Wire.id(cardID),
            "destination_account_id": Wire.id(destinationAccountID), "frequency": frequencyRaw, "interval": interval,
            "start_date": Wire.date(startDate), "next_date": Wire.date(nextDate), "end_date": Wire.date(endDate),
            "is_subscription": isSubscription, "auto_confirm": autoConfirm, "is_paused": isPaused, "note": Wire.value(note),
            "tags": TagsText.decode(tagsText), "source": sourceRaw ?? RecordSource.app.rawValue,
            "merchant_id": Wire.id(merchantID), "via_merchant_id": Wire.id(viaMerchantID),
        ]) { $1 }
    }
}

extension SavingsGoalRecord: SyncableRecord {
    static var syncEntity: String { "savingsGoal" }
    var syncID: String { Wire.id(id) }

    func wireRow() throws -> WireRow {
        Wire.audit(self).merging([
            "id": Wire.id(id), "name": name, "target_amount": targetAmount, "target_currency": targetCurrency, "saved": saved,
            "target_month": Wire.value(targetMonth), "target_year": Wire.value(targetYear), "icon": Wire.value(icon),
            "color": Wire.value(color),
        ]) { $1 }
    }
}

extension LoanRecord: SyncableRecord {
    static var syncEntity: String { "loan" }
    var syncID: String { Wire.id(id) }

    func wireRow() throws -> WireRow {
        Wire.audit(self).merging([
            "id": Wire.id(id), "name": name, "lender": Wire.value(lender), "borrowed_amount": borrowedAmount,
            "borrowed_currency": borrowedCurrency, "installment_amount": installmentAmount, "installment_count": installmentCount,
            "frequency": frequencyRaw, "first_due_date": Wire.date(firstDueDate),
        ]) { $1 }
    }

    /// One payment as its own row (`loanPayment`), dated like the loan that holds it.
    func paymentRow(_ payment: LoanPayment, deletedAt: Date? = nil) -> WireRow {
        [
            "id": Wire.id(NameBasedID.loanPayment(loanID: id, number: payment.number)), "loan_id": Wire.id(id), "number": payment.number,
            "paid_at": Wire.date(payment.paidAt), "transaction_id": Wire.id(payment.transactionID),
            "created_at": Wire.date(createdAt), "updated_at": Wire.date(deletedAt ?? updatedAt), "deleted_at": Wire.date(deletedAt),
        ]
    }
}

extension PersonalDebtRecord: SyncableRecord {
    static var syncEntity: String { "personalDebt" }
    var syncID: String { Wire.id(id) }

    func wireRow() throws -> WireRow {
        Wire.audit(self).merging([
            "id": Wire.id(id), "person": person, "direction": directionRaw, "amount": amount, "currency": currency,
            "date": Wire.date(date), "note": Wire.value(note), "settled_at": Wire.date(settledAt), "transaction_id": Wire.id(transactionID),
            // Always sent, null for none: removing the date has to clear it on the other devices.
            "due_date": Wire.date(dueDate),
        ]) { $1 }
    }

    func repaymentRow(_ repayment: DebtRepayment, deletedAt: Date? = nil) -> WireRow {
        [
            "id": Wire.id(repayment.id), "debt_id": Wire.id(id), "amount": DecimalCoding.string(repayment.amount),
            "date": Wire.date(repayment.date),
            "created_at": Wire.date(createdAt), "updated_at": Wire.date(deletedAt ?? updatedAt), "deleted_at": Wire.date(deletedAt),
        ]
    }
}

extension CategorizationRuleRecord: SyncableRecord {
    static var syncEntity: String { "categorizationRule" }
    var syncID: String { Wire.id(id) }

    func wireRow() throws -> WireRow {
        Wire.audit(self).merging([
            "id": Wire.id(id), "match": match, "category_id": categoryID, "kind": kindRaw, "tags": TagsText.decode(tagsText),
            "sort_index": sortIndex, "merchant_id": Wire.id(merchantID),
        ]) { $1 }
    }
}

extension MerchantRecord: SyncableRecord {
    static var syncEntity: String { "merchant" }
    var syncID: String { Wire.id(id) }

    func wireRow() throws -> WireRow {
        Wire.audit(self).merging([
            "id": Wire.id(id), "name": name, "domain": Wire.value(domain), "brand_id": Wire.value(brandID),
            "default_category_id": Wire.value(defaultCategoryID), "is_platform": isPlatform,
        ]) { $1 }
    }
}

extension NotificationStateRecord: SyncableRecord {
    static var syncEntity: String { "notificationState" }
    var syncID: String { id }

    func wireRow() throws -> WireRow {
        Wire.audit(self).merging([
            "id": id, "read_at": Wire.date(readAt), "dismissed_at": Wire.date(dismissedAt),
        ]) { $1 }
    }
}

extension SettingsRecord {
    /// Only what is the same on every device; unlock, relock, hiding amounts and the iCloud switch stay here.
    /// `time_zone` is left out while there is none, never sent as null: the server keeps the zone a
    /// row lacks, so a save here can't clear one another device set.
    func wireRow() -> WireRow {
        var row: WireRow = [
            "id": "settings", "principal": principal, "second": Wire.value(second == principal ? nil : second), "rate": rate,
            "payment_reminder_days_before": paymentReminderDaysBefore, "has_completed_onboarding": hasCompletedOnboarding,
            "created_at": Wire.date(updatedAt), "updated_at": Wire.date(updatedAt), "deleted_at": NSNull(),
        ]
        if let timeZone {
            row["time_zone"] = timeZone
        }
        return row
    }
}
