import Foundation

/// The app's own unlock code: six digits, like the iPhone's and most banking apps'. Only its
/// salted hash is ever stored.
public struct Passcode: Hashable, Sendable {
    public static let length = 6

    public let digits: String

    public init(_ digits: String) throws(DomainError) {
        guard digits.count == Self.length, digits.allSatisfy({ $0.isASCII && $0.isNumber }) else {
            throw .invalidPasscode
        }
        self.digits = digits
    }

    /// One digit repeated, or a run up or down ("123456", "987654", also wrapping "890123").
    public var isTooSimple: Bool {
        let values = digits.compactMap(\.wholeNumberValue)
        let steps = Set(zip(values, values.dropFirst()).map { ($1 - $0 + 10) % 10 })
        return steps.count == 1 && [0, 1, 9].contains(steps.first)
    }
}

/// Wrong passcode entries in a row, kept across launches so quitting the app doesn't reset the
/// lockout.
public struct PasscodeAttempts: Hashable, Sendable, Codable {
    public var failures: Int
    public var lastFailure: Date?

    public init(failures: Int = 0, lastFailure: Date? = nil) {
        self.failures = failures
        self.lastFailure = lastFailure
    }

    public static let empty = Self()
}
