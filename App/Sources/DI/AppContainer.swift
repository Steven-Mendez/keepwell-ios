import Core
import Domain
import Foundation
import Persistence
import SwiftData
#if DEBUG
import DomainSamples
#endif

/// Composition root: the only place that names concrete types and wires Data → Domain → Presentation.
/// Features see protocols only, so swapping storage (e.g. for UI tests) is a change here alone.
final class AppContainer {
    let currencyFormatter = CurrencyFormatter()
    let store: SwiftDataStore

    init(modelContainer: ModelContainer) {
        store = SwiftDataStore(modelContainer: modelContainer)
    }

    #if DEBUG
    /// Blocks launch until the sample is written so the first screen already shows it.
    func seedSampleData() {
        let sample = SampleData(referenceDate: .now)
        let store = store
        let semaphore = DispatchSemaphore(value: 0)
        Task.detached {
            try? await store.seed(
                settings: sample.settings,
                accounts: sample.accounts,
                cards: sample.cards,
                transactions: sample.transactions,
                categories: sample.categories,
            )
            semaphore.signal()
        }
        semaphore.wait()
    }
    #endif
}
