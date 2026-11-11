import Foundation

/// A place the keyboard can jump to: the four tabs, the sections Home pushes and Settings. Same
/// set and letters as the web's `MAIN_NAV`, `SECTION_NAV` and `SETTINGS_NAV`.
public enum ShortcutDestination: CaseIterable, Hashable, Sendable {
    case home
    case transactions
    case accounts
    case summary
    case recurring
    case goals
    case debts
    case settings

    /// The letter that follows "g" ("," for Settings).
    public var jumpKey: Character {
        switch self {
        case .home: "h"
        case .transactions: "t"
        case .accounts: "a"
        case .summary: "s"
        case .recurring: "r"
        case .goals: "g"
        case .debts: "d"
        case .settings: ","
        }
    }

    /// The digit that jumps straight to a tab; the sections have none.
    public var digit: Int? {
        switch self {
        case .home: 1
        case .transactions: 2
        case .accounts: 3
        case .summary: 4
        default: nil
        }
    }
}

/// Which kind of movement a shortcut starts. `any` asks "What are you recording?".
public enum ShortcutMovement: Hashable, Sendable {
    case any
    case expense
    case income
    case transfer
}

/// What a keyboard shortcut or a search suggestion asks the app to do. `RootView` performs it.
public enum ShortcutCommand: Hashable, Sendable {
    /// The search field of Transactions, the iOS counterpart of the web's command palette.
    case search
    case newMovement(ShortcutMovement)
    case goTo(ShortcutDestination)
    case showShortcuts

    /// The palette's "Actions".
    public static let actions: [Self] = [
        .newMovement(.expense), .newMovement(.income), .newMovement(.transfer),
    ]

    /// The palette's "Go to", in the web's order.
    public static let destinations: [Self] = ShortcutDestination.allCases.map { .goTo($0) }
}

/// Turns plain key presses into commands, the way the web's `keyboard-shortcuts.tsx` does: single
/// letters, digits, "," "/" "?", and "g" followed by a section letter within `timeout`.
/// Whether a field or sheet owns the keyboard is the caller's call: it doesn't feed keys then.
public struct KeyboardShortcutSequence: Sendable {
    public enum Outcome: Equatable, Sendable {
        /// Not a shortcut: the key goes on to whatever else wants it.
        case ignored
        /// "g" was pressed and waits for its letter.
        case pending
        case run(ShortcutCommand)
    }

    /// The web waits 1.2 s for the letter after "g".
    public static let timeout: TimeInterval = 1.2

    private var pendingSince: Date?

    public init() {}

    public mutating func press(_ character: Character, at now: Date = .now) -> Outcome {
        let key = Character(character.lowercased())
        if let since = pendingSince {
            pendingSince = nil
            if now.timeIntervalSince(since) <= Self.timeout {
                // The letter after "g" is consumed whether or not it names a section, like the web.
                return ShortcutDestination.allCases.first { $0.jumpKey == key }.map { .run(.goTo($0)) } ?? .ignored
            }
        }
        switch key {
        case "g":
            pendingSince = now
            return .pending
        case "n": return .run(.newMovement(.any))
        case "e": return .run(.newMovement(.expense))
        case "i": return .run(.newMovement(.income))
        case "t": return .run(.newMovement(.transfer))
        case ",": return .run(.goTo(.settings))
        case "/": return .run(.search)
        case "?": return .run(.showShortcuts)
        default:
            if let digit = key.wholeNumberValue, let target = ShortcutDestination.allCases.first(where: { $0.digit == digit }) {
                return .run(.goTo(target))
            }
            return .ignored
        }
    }
}
