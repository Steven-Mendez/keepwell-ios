import Core
import Domain
import Foundation
import HomeDomain

/// "End of month": what the bank and cash accounts should hold when the month closes, and the
/// lines that add up to it.
extension HomeViewModel {
    public struct ForecastLine: Identifiable, Equatable {
        public var id: String {
            title
        }

        public let title: String
        /// Signed: what adds is "+", what takes away is "−".
        public let amount: String
    }

    /// "≈ C$12,400", rounded to whole units since it's an estimate.
    func forecastTotal(_ forecast: BalanceForecast, hidden: Bool) -> String {
        guard !hidden else { return Self.maskedAmount }
        let amount = formatter.string(from: forecast.total, currencyCode: forecast.currency, fractionDigits: 0)
        return String(localized: "≈ \(amount)", bundle: #bundle)
    }

    var forecastExplanation: String {
        String(localized: "What your bank and cash accounts would hold, counting what's planned and your usual spending.", bundle: #bundle)
    }

    /// Available today, then what is still to come in (+) and go out (−) this month.
    func forecastLines(_ forecast: BalanceForecast, hidden: Bool) -> [ForecastLine] {
        let currency = forecast.currency
        let line = { (title: String, amount: Decimal, sign: CurrencyFormatter.Sign) in
            ForecastLine(
                title: title,
                amount: hidden ? Self.maskedAmount : self.formatter.string(
                    from: amount,
                    currencyCode: currency,
                    fractionDigits: 0,
                    sign: amount == 0 ? .automatic : sign,
                ),
            )
        }
        return [
            line(String(localized: "Available today", bundle: #bundle), forecast.availableToday, .automatic),
            line(String(localized: "Planned income", bundle: #bundle), forecast.plannedIncome, .always),
            line(String(localized: "Planned expenses", bundle: #bundle), -forecast.plannedExpenses, .always),
            line(String(localized: "Card payments", bundle: #bundle), -forecast.cardPayments, .always),
            line(String(localized: "Usual spending", bundle: #bundle), -forecast.usualSpending, .always),
        ]
    }
}
