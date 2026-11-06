import Domain
import Foundation

/// How recurring rules read wherever they show: the recurring screen, home, a movement's menu and
/// the "Repeat" choice when logging a movement.
public enum RecurringDisplay {
    /// "Every month", "Every 2 weeks", "Every year".
    public static func frequency(_ frequency: RecurringFrequency, interval: Int = 1) -> String {
        switch frequency {
        case .weekly: String(localized: "Every \(interval) weeks", bundle: #bundle)
        case .monthly: String(localized: "Every \(interval) months", bundle: #bundle)
        case .yearly: String(localized: "Every \(interval) years", bundle: #bundle)
        }
    }

    public static func frequency(of rule: RecurringRule) -> String {
        frequency(rule.frequency, interval: rule.interval)
    }

    /// "Recurring · Every month", on a movement a rule recorded.
    public static func badge(of rule: RecurringRule) -> String {
        let frequency = frequency(of: rule)
        return String(localized: "Recurring · \(frequency)", bundle: #bundle)
    }

    /// "Today", "Tomorrow", or the day ("Nov 12"), in the person's language.
    public static func day(_ date: Date, today: Date = .now, calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: today) {
            return String(localized: "Today", bundle: #bundle)
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: today), calendar.isDate(date, inSameDayAs: tomorrow) {
            return String(localized: "Tomorrow", bundle: #bundle)
        }
        // Spanish abbreviates months with a trailing dot ("nov."), which reads badly mid-sentence.
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: today)
        let style: Date.FormatStyle = sameYear ? .dateTime.day().month(.abbreviated) : .dateTime.day().month(.abbreviated).year()
        return date.formatted(style).replacingOccurrences(of: ".", with: "")
    }
}
