import Domain
import Foundation
import LockDomain

/// The lock feature's wording, shared by the lock screen and the passcode setup.
enum LockStrings {
    static var passcodeLength: Int {
        Passcode.length
    }

    static var reason: String {
        String(localized: "Unlock Keepwell to see your finances.", bundle: #bundle)
    }

    static var recoveryReason: String {
        String(localized: "Use your iPhone passcode to get back into Keepwell. Your Keepwell passcode will be turned off.", bundle: #bundle)
    }

    static var enterPasscode: String {
        String(localized: "Enter passcode", bundle: #bundle)
    }

    static func wrongPasscode(remaining: Int) -> String {
        String(localized: "Wrong passcode. \(remaining) tries left.", bundle: #bundle)
    }

    static func greeting(_ part: DayPart, name: String?) -> String {
        guard let name, !name.isEmpty else {
            return switch part {
            case .morning: String(localized: "Good morning", bundle: #bundle)
            case .afternoon: String(localized: "Good afternoon", bundle: #bundle)
            case .evening: String(localized: "Good evening", bundle: #bundle)
            }
        }
        return switch part {
        case .morning: String(localized: "Good morning, \(name)", bundle: #bundle)
        case .afternoon: String(localized: "Good afternoon, \(name)", bundle: #bundle)
        case .evening: String(localized: "Good evening, \(name)", bundle: #bundle)
        }
    }

    /// "0:30", "14:59": what's left of a lockout.
    static func remaining(until date: Date, now: Date) -> String {
        Duration.seconds(max(0, date.timeIntervalSince(now).rounded(.up))).formatted(.time(pattern: .minuteSecond))
    }
}
