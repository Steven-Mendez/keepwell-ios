import FeatureTestSupport
import SwiftUI
import Testing
@testable import AddCardPresentation

@Suite("Type snapshots")
@MainActor
struct TypeSnapshotTests {
    @Test
    func type() async {
        await assertScreenSnapshot(of: AddCardTypeView(viewModel: AddCardFactory.loaded()) {})
    }
}
