import Domain
import DomainSamples
import Foundation
import Testing
@testable import SettingsDomain

@Suite("Payment methods")
struct PaymentMethodsTests {
    @Test
    func methodsAreGroupedByAccountWithPlasticsFirst() async throws {
        let store = InMemoryStore(sample: .standard)
        let groups = try await DefaultGetPaymentMethodsUseCase(accounts: store, cards: store).execute()
        let cards = await store.fetchCards()
        #expect(groups.flatMap(\.methods).count == cards.count)
        #expect(!groups.contains { $0.account.kind == .cash })
        let savings = try #require(groups.first { $0.account.id == SampleData.IDs.savings })
        #expect(savings.methods.map(\.kind) == [.debit, .transfer])
    }
}
