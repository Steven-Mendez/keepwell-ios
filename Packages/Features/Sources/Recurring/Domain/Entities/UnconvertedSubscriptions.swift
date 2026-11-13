import Foundation

/// Live expense subscriptions in one currency the settings can't convert, so no total counts them
/// (web `UnconvertedSubscriptions`).
public struct UnconvertedSubscriptions: Hashable, Sendable {
    public let currency: String
    public let count: Int

    public init(currency: String, count: Int) {
        self.currency = currency
        self.count = count
    }
}
