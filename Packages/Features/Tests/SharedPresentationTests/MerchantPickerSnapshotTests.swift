import Domain
import FeatureTestSupport
import SwiftUI
import Testing
@testable import SharedPresentation

/// The "Business" and "Via" sheets. Without a brand search (`search: nil`) only the person's
/// merchants and the brand table show, so the references never depend on the network.
@Suite("Merchant picker snapshots")
@MainActor
struct MerchantPickerSnapshotTests {
    private let subway = Merchant(name: "Subway", domain: "subway.com", brandID: "subway")
    private let corner = Merchant(name: "Pulpería La Esquina")
    private let uberEats = Merchant(name: "Uber Eats", domain: "ubereats.com", isPlatform: true)

    private func picker(role: MerchantRole, query: String = "", current: MerchantChoice? = nil) -> MerchantPickerView {
        let viewModel = MerchantPickerViewModel(
            role: role, merchants: [subway, corner, uberEats], current: current, search: nil, debounce: .zero,
        ) { _ in }
        viewModel.query = query
        return MerchantPickerView(viewModel: viewModel)
    }

    @Test
    func business() {
        assertScreenSnapshot(of: picker(role: .business, current: .merchant(subway.id)))
    }

    /// Typing shows your matches, the table's brands and "Add “…”".
    @Test
    func businessSearch() {
        assertScreenSnapshot(of: picker(role: .business, query: "sub"))
    }

    /// Platforms first.
    @Test
    func via() {
        assertScreenSnapshot(of: picker(role: .via))
    }
}
