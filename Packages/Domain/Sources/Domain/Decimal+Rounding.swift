import Foundation

extension Decimal {
    /// Defaults to banker's rounding so repeated rounding of ratios doesn't drift upward.
    public func rounded(scale: Int, mode: NSDecimalNumber.RoundingMode = .bankers) -> Decimal {
        var source = self
        var result = Decimal()
        NSDecimalRound(&result, &source, scale, mode)
        return result
    }
}
