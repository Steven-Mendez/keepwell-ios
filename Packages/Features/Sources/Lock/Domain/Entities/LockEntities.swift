import Domain
import Foundation

/// Part of the day the greeting names. Domain keeps the hour ranges; Presentation words them.
public enum DayPart: Sendable, Equatable {
    case morning
    case afternoon
    case evening

    /// Morning from 5:00, afternoon from 12:00, evening from 19:00, the way people greet in
    /// English and Spanish alike.
    public init(date: Date, calendar: Calendar = .current) {
        switch calendar.component(.hour, from: date) {
        case 5 ..< 12: self = .morning
        case 12 ..< 19: self = .afternoon
        default: self = .evening
        }
    }
}

/// What the lock screen needs before it shows.
public struct LockContext: Sendable, Equatable {
    /// With an app passcode the screen shows the keypad; without one it falls back to the
    /// iPhone's own passcode sheet.
    public let hasPasscode: Bool
    public let preferredName: String?
    /// Set while too many wrong entries keep the keypad disabled.
    public let lockedUntil: Date?

    public init(hasPasscode: Bool, preferredName: String?, lockedUntil: Date?) {
        self.hasPasscode = hasPasscode
        self.preferredName = preferredName
        self.lockedUntil = lockedUntil
    }
}

/// The outcome of one passcode entry.
public enum PasscodeAttemptResult: Sendable, Equatable {
    case unlocked
    /// Mistakes left before the keypad closes for a while.
    case wrong(remainingBeforeLockout: Int)
    case lockedOut(until: Date)
}

/// How long a run of wrong passcodes keeps the keypad closed. The first few are free, since
/// typos happen; after that each mistake waits longer, as the iPhone's own lock does, so guessing
/// a million codes takes years. Nothing is ever erased: this is a personal app, and a wipe would
/// hurt the owner more than a thief.
public enum LockoutPolicy {
    public static let freeAttempts = 5
    static let delays: [TimeInterval] = [30, 60, 5 * 60, 15 * 60, 60 * 60]

    /// The wait after `failures` wrong entries in a row; zero while still free.
    public static func delay(afterFailures failures: Int) -> TimeInterval {
        guard failures >= freeAttempts else { return 0 }
        return delays[min(failures - freeAttempts, delays.count - 1)]
    }

    public static func lockedUntil(_ attempts: PasscodeAttempts, now: Date) -> Date? {
        guard let last = attempts.lastFailure else { return nil }
        let delay = delay(afterFailures: attempts.failures)
        guard delay > 0 else { return nil }
        // A clock set back before the last failure would otherwise stretch the wait without end.
        let start = min(last, now)
        let until = start.addingTimeInterval(delay)
        return until > now ? until : nil
    }
}
