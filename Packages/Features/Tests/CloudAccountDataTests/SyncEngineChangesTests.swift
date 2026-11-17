import CloudAccountData
import Foundation
import Testing

/// What a round tells the app about changes made elsewhere.
extension SyncEngineTests {
    /// The app reloads the screen in front on it, so a change from elsewhere appears in place.
    @Test
    func aRoundSaysWhetherItBroughtChanges() async throws {
        let store = FakeSyncStore()
        let suite = suite()
        UserDefaults(suiteName: suite)?.set(0, forKey: "sync.cursor")
        StubProtocol.handler = Self.serveThreeCategories
        let engine = engine(store, suite: suite)

        try await engine.syncOnce()
        #expect(await engine.lastRoundBroughtChanges)

        StubProtocol.handler = { request in
            request.url?.path == "/sync/pull"
                ? (200, [:], Self.json(["changes": [], "next_cursor": 3, "has_more": false]))
                : (404, [:], Data())
        }
        try await engine.syncOnce()
        #expect(await engine.lastRoundBroughtChanges == false)
    }
}
