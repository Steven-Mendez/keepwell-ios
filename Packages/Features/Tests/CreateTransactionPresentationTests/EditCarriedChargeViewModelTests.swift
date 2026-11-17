import CreateTransactionDomain
import Domain
import DomainSamples
import Foundation
import Testing
@testable import CreateTransactionPresentation

/// An edit opens with the charge its movement was saved with; changing what it was charged for clears it.
@Suite("The charge an edited movement opens with")
@MainActor
struct EditCarriedChargeViewModelTests {
    private typealias IDs = SampleData.IDs
    private let now = SampleData.defaultReferenceDate

    private func editing(_ description: String, in store: InMemoryStore) async throws -> CreateTransactionViewModel {
        let movement = try #require(await store.fetchTransactions(in: nil).first { $0.description == description })
        let stored = DefaultGetTransactionContextUseCase(
            settings: store, categories: store, accounts: store, cards: store, transactions: store, rules: store, now: { now },
        )
        let viewModel = CreateTransactionViewModel(
            stored: .edit(movement.id),
            getStored: stored,
            update: DefaultUpdateTransactionUseCase(stored: stored, transactions: store, settings: store),
            now: { now },
        )
        await viewModel.load()
        return viewModel
    }

    /// "Movies": C$739.32 from savings, charged US$20.42.
    private func editingMovies(in store: InMemoryStore = InMemoryStore(sample: .standard)) async throws -> CreateTransactionViewModel {
        try await editing("Movies", in: store)
    }

    @Test
    func staysWhileTheAmountAndCurrencyDo() async throws {
        let store = InMemoryStore(sample: .standard)
        let viewModel = try await editingMovies(in: store)
        #expect(viewModel.debitedText == "20.42")
        viewModel.description = "Cinema"
        viewModel.amountText = "739.320"
        viewModel.currency = "NIO"
        #expect(viewModel.debitedText == "20.42")
        #expect(viewModel.draft.actualDebitedPrincipal == Decimal(string: "20.42"))
        await viewModel.saveChanges()
        let saved = await store.fetchTransactions(in: nil).first { $0.description == "Cinema" }
        #expect(saved?.actualDebitedPrincipal == Decimal(string: "20.42"))
    }

    @Test
    func clearsWhenTheAmountChanges() async throws {
        let viewModel = try await editingMovies()
        viewModel.press(.delete)
        #expect(viewModel.amountText == "739.3")
        #expect(viewModel.debitedText.isEmpty)
    }

    @Test
    func clearsWhenTheCurrencyChanges() async throws {
        let viewModel = try await editingMovies()
        viewModel.currency = "USD"
        #expect(viewModel.debitedText.isEmpty)
    }

    @Test
    func leavesAChargeThePersonTyped() async throws {
        let viewModel = try await editingMovies()
        viewModel.debitedText = "22.10"
        viewModel.press(.delete)
        viewModel.currency = "USD"
        #expect(viewModel.debitedText == "22.10")
    }

    @Test
    func aMovementInThePrincipalCurrencyCarriesNone() async throws {
        let store = InMemoryStore(sample: .standard)
        await store.save(Transaction(
            date: now, description: "Hosting", kind: .expense, categoryID: "subscriptions", amount: 20,
            currency: "USD", accountID: IDs.savings, actualDebitedPrincipal: 21,
            exchangeRate: SampleData.standard.settings.currencies.exchangeRate,
        ))
        let viewModel = try await editing("Hosting", in: store)
        #expect(viewModel.debitedText.isEmpty)
        #expect(viewModel.carriedDebitText.isEmpty)
    }
}
