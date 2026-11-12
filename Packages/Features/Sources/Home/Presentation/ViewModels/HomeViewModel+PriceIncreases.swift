import Domain
import Foundation
import HomeDomain

/// Subscriptions that just charged more than before: shown on home and sent as a notification once
/// per charge.
extension HomeViewModel {
    public struct PriceIncreaseAlert: Identifiable, Equatable {
        public var id: UUID {
            increase.transactionID
        }

        public let increase: PriceIncrease
        /// "Netflix went up in price".
        public let title: String
        /// "Now $12.99, before $9.99."
        public let body: String
    }

    public var priceIncreaseAlerts: [PriceIncreaseAlert] {
        guard let overview else { return [] }
        return overview.priceIncreases.map { increase in
            let name = increase.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let current = formatter.string(increase.current)
            let previous = formatter.string(increase.previous)
            return PriceIncreaseAlert(
                increase: increase,
                title: String(localized: "\(name) went up in price", bundle: #bundle),
                body: String(localized: "Now \(current), before \(previous).", bundle: #bundle),
            )
        }
    }
}
