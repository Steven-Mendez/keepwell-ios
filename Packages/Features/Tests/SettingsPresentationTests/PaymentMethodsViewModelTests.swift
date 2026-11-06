import Domain
import DomainSamples
import Foundation
import SettingsDomain
import Testing
@testable import SettingsPresentation

@MainActor
@Suite("Payment methods screen")
struct PaymentMethodsViewModelTests {
    private let calendar = Calendar(identifier: .gregorian)

    private func viewModel(now: Date) -> PaymentMethodsViewModel {
        let store = InMemoryStore(sample: .standard)
        return PaymentMethodsViewModel(
            getMethods: DefaultGetPaymentMethodsUseCase(accounts: store, cards: store),
            now: { now },
            calendar: calendar,
        )
    }

    private func card(expiring month: Int, _ year: Int) throws -> Card {
        try Card(accountID: UUID(), kind: .creditHolder, network: .visa, lastFour: "0633", expiry: CardExpiry(month: month, year: year))
    }

    @Test
    func expiryReadsAsValidExpiringOrExpired() throws {
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 3)))
        let model = viewModel(now: now)
        #expect(try model.subtitle(of: card(expiring: 9, 2028)) == ("Credit · valid thru 09/28", false))
        #expect(try model.subtitle(of: card(expiring: 11, 2026)) == ("Credit · expires this month", true))
        #expect(try model.subtitle(of: card(expiring: 2, 2026)) == ("Credit · expired 02/26", true))
    }

    @Test
    func loadsEveryAccountWithMethods() async {
        let model = viewModel(now: .now)
        await model.load()
        #expect(!model.groups.isEmpty)
        #expect(!model.hasFailed)
    }
}
