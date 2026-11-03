import Core
import Foundation
import SwiftData

/// Composition root: the only place that names concrete types and wires Data → Domain → Presentation.
/// Features see protocols only, so swapping storage (e.g. for UI tests) is a change here alone.
final class AppContainer {
    let currencyFormatter = CurrencyFormatter()

    private let modelContainer: ModelContainer

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }
}
