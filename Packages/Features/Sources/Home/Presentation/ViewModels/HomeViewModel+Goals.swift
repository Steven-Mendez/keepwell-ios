import Domain
import Foundation

/// The goals card: the first goal in list order (the one most in need of attention).
extension HomeViewModel {
    /// "C$4,500.00 of C$15,000.00", masked with the rest of home's amounts.
    func goalAmounts(_ progress: SavingsGoalProgress, hidden: Bool) -> String {
        let currency = progress.goal.target.currency
        let saved = visible(formatter.string(from: progress.goal.saved, currencyCode: currency), hidden: hidden)
        let target = visible(formatter.string(from: progress.goal.target.amount, currencyCode: currency), hidden: hidden)
        return String(localized: "\(saved) of \(target)", bundle: #bundle)
    }

    /// The bar stops at full even for an overshot goal.
    func goalBarFraction(_ progress: SavingsGoalProgress) -> Double {
        min(max(NSDecimalNumber(decimal: progress.fraction).doubleValue, 0), 1)
    }
}
