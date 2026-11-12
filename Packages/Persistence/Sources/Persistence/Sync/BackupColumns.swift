import Domain
import Foundation

// The columns of every wire row (`wire-columns.json` in the shared fixtures, from keepwell-web's
// `schema/sync.ts`), for checking a backup before anything is written: "name:type", where the type
// is s(tring), n(umber), b(oolean) or a(rray), `?` allows null and `~` allows the key to be absent.
// `BackupColumnsTests` keeps this equal to the fixture.

enum BackupColumns {
    struct Column: Equatable {
        let name: String
        let type: Character
        let nullable: Bool
        let optional: Bool
    }

    static let spec: [String: String] = [
        "account": "id:s name:s bank:s? kind:s opening_balances:a opening_date:s debt_mode:s? limit_amount:s? "
            + "limit_currency:s? cutoff_day:n? due_day:n? created_at:s updated_at:s deleted_at:s?",
        "card": "id:s account_id:s kind:s network:s? last_four:s? color:s? product_name:s? expiry_month:n? "
            + "expiry_year:n? created_at:s updated_at:s deleted_at:s?",
        "category": "id:s name:s kind:s icon:s? color:s? is_renamed:b sort_index:n budget_amount:s? budget_currency:s? "
            + "created_at:s updated_at:s deleted_at:s?",
        "transaction": "id:s date:s status:s description:s kind:s category_id:s? amount:s currency:s account_id:s card_id:s? "
            + "destination_account_id:s? actual_debited_principal:s? rate_principal:s rate_second:s rate:s "
            + "is_shared:b note:s? recurring_id:s? tags:a source:s~ created_at:s updated_at:s deleted_at:s?",
        "recurringRule": "id:s name:s kind:s category_id:s? amount:s currency:s account_id:s card_id:s? "
            + "destination_account_id:s? frequency:s interval:n start_date:s next_date:s end_date:s? "
            + "is_subscription:b auto_confirm:b is_paused:b note:s? tags:a source:s~ created_at:s updated_at:s "
            + "deleted_at:s?",
        "savingsGoal": "id:s name:s target_amount:s target_currency:s saved:s target_month:n? target_year:n? icon:s? "
            + "color:s? created_at:s updated_at:s deleted_at:s?",
        "loan": "id:s name:s lender:s? borrowed_amount:s borrowed_currency:s installment_amount:s installment_count:n "
            + "frequency:s first_due_date:s created_at:s updated_at:s deleted_at:s?",
        "loanPayment": "id:s loan_id:s number:n paid_at:s transaction_id:s? created_at:s updated_at:s deleted_at:s?",
        "personalDebt": "id:s person:s direction:s amount:s currency:s date:s note:s? settled_at:s? transaction_id:s? "
            + "due_date:s?~ created_at:s updated_at:s deleted_at:s?",
        "personalDebtRepayment": "id:s debt_id:s amount:s date:s created_at:s updated_at:s deleted_at:s?",
        "categorizationRule": "id:s match:s category_id:s kind:s tags:a sort_index:n created_at:s updated_at:s deleted_at:s?",
        "settings": "id:s principal:s second:s? rate:s payment_reminder_days_before:n has_completed_onboarding:b "
            + "time_zone:s?~ created_at:s updated_at:s deleted_at:s?",
        "notificationState": "id:s read_at:s? dismissed_at:s? created_at:s updated_at:s deleted_at:s?",
    ]

    static let entities: [String: [Column]] = spec.mapValues { text in
        text.split(separator: " ").map { item in
            let parts = item.split(separator: ":")
            let flags = parts[1].dropFirst()
            return Column(name: String(parts[0]), type: parts[1].first ?? "s", nullable: flags.contains("?"), optional: flags.contains("~"))
        }
    }

    /// Exact decimal text, as the web's `DECIMAL_PATTERN`: no exponent, grouping or locale.
    static let decimalColumns: Set<String> = [
        "amount", "rate", "actual_debited_principal", "limit_amount", "budget_amount", "saved", "target_amount",
        "borrowed_amount", "installment_amount",
    ]

    static let idColumns: Set<String> = [
        "account_id", "card_id", "destination_account_id", "recurring_id", "loan_id", "debt_id", "transaction_id",
    ]

    /// The first column of `row` that doesn't fit its entity, or `nil` when the row is well formed.
    static func problem(entity: String, row: [String: Any]) -> String? {
        guard let columns = entities[entity] else { return "entity" }
        for column in columns {
            guard let value = row[column.name] else {
                if column.optional {
                    continue
                }
                return column.name
            }
            if value is NSNull {
                if column.nullable {
                    continue
                }
                return column.name
            }
            guard fits(value, column.type), wellFormed(column.name, value) else { return column.name }
        }
        if entity != "category", entity != "notificationState", entity != "settings", !isUUID(row["id"]) {
            return "id"
        }
        return nil
    }

    private static func fits(_ value: Any, _ type: Character) -> Bool {
        let isBoolean = (value as? NSNumber).map { CFGetTypeID($0) == CFBooleanGetTypeID() } ?? false
        return switch type {
        case "s": value is String
        case "n": value is NSNumber && !isBoolean
        case "b": isBoolean
        case "a": value is [Any]
        default: false
        }
    }

    private static func wellFormed(_ name: String, _ value: Any) -> Bool {
        if decimalColumns.contains(name) {
            return (value as? String).map(isDecimal) ?? false
        }
        if idColumns.contains(name) {
            return isUUID(value)
        }
        if name == "time_zone" {
            return (value as? String).map(HomeTimeZone.isWellFormed) ?? false
        }
        if name == "opening_balances" {
            return (value as? [[String: Any]])?.allSatisfy { ($0["amount"] as? String).map(isDecimal) ?? false } ?? false
        }
        if name.hasSuffix("_at") || name.hasSuffix("_date") || name == "date" {
            return (value as? String).flatMap(WireReader.parse) != nil
        }
        return true
    }

    static func isDecimal(_ text: String) -> Bool {
        text.wholeMatch(of: /-?[0-9]+(\.[0-9]+)?/) != nil
    }

    private static func isUUID(_ value: Any?) -> Bool {
        (value as? String).flatMap(UUID.init(uuidString:)) != nil
    }
}
