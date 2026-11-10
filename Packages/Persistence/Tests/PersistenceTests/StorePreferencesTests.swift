import Domain
import Foundation
import Testing
@testable import Persistence

@Suite("Store preferences")
struct StorePreferencesTests {
    private func makePreferences() throws -> StorePreferences {
        let defaults = try #require(UserDefaults(suiteName: "StorePreferencesTests.\(UUID().uuidString)"))
        return StorePreferences(defaults: defaults)
    }

    @Test
    func thePreferredNameIsTrimmedAndABlankOneIsForgotten() async throws {
        let preferences = try makePreferences()
        await preferences.setPreferredName("  Ana ")
        #expect(await preferences.preferredName() == "Ana")
        await preferences.setPreferredName("  ")
        #expect(await preferences.preferredName() == nil)
    }
}
