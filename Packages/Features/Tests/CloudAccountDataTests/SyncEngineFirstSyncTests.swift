import CloudAccountData
import CloudAccountDomain
import Domain
import Foundation
import Testing

/// The first sync of this device with an account: who has data decides what happens.
extension SyncEngineTests {
    private static func row(_ id: String, name: String = "Row", deleted: Bool = false) -> [String: Any] {
        [
            "id": id, "name": name, "created_at": "2026-11-01T00:00:00.000Z", "updated_at": "2026-11-01T00:00:00.000Z",
            "deleted_at": deleted ? "2026-11-02T00:00:00.000Z" : NSNull(),
        ]
    }

    /// Serves a snapshot with `rows` per entity, and empty pushes and pulls.
    private static func serve(_ rows: [String: [[String: Any]]]) {
        StubProtocol.handler = { request in
            switch request.url?.path {
            case "/sync/snapshot":
                let query = request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?.queryItems ?? []
                let entity = query.first { $0.name == "entity" }?.value ?? ""
                return (200, [:], json(["rows": rows[entity] ?? [], "server_seq": 7, "next_after": NSNull()]))
            case "/sync/push":
                // The body arrives as a stream; StubProtocol records it before asking for an answer.
                let sent = StubProtocol.requests.last?.httpBody ?? request.httpBody
                let body = sent.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
                let events = body?["events"] as? [[String: Any]] ?? []
                let results = events.map { ["event_id": $0["event_id"] ?? "", "status": "applied"] }
                return (200, [:], json(["results": results, "partial": false]))
            default:
                return (200, [:], json(["changes": [], "next_cursor": 7, "has_more": false]))
            }
        }
    }

    private func paths() -> [String] {
        StubProtocol.requests.compactMap(\.url?.path)
    }

    @Test
    func bothSidesWithDataStopForAChoiceWithoutSendingOrApplyingAnything() async throws {
        let store = FakeSyncStore(events: [event("groceries", name: "Mine")], counts: ["transaction": 12, "account": 3])
        let suite = suite()
        Self.serve([
            "account": [Self.row("a1"), Self.row("a2", deleted: true)],
            "transaction": [Self.row("t1"), Self.row("t2")],
            "category": [Self.row("food")],
        ])
        let outcome = try await engine(store, suite: suite).syncOnce(account: "u1")
        let expected = SyncConflict(
            device: SyncDataSummary(movements: 12, accounts: 3),
            account: SyncDataSummary(movements: 2, accounts: 1),
        )
        #expect(outcome == .needsChoice(expected))
        #expect(!paths().contains("/sync/push"))
        #expect(!paths().contains("/sync/pull"))
        #expect(await store.appliedCount() == 0)
        #expect(await store.pendingCount() == 1)
        #expect(cursor(suite) == nil)
    }

    @Test
    func onlyTheAccountHasDataSoItComesDownWholeWithoutAsking() async throws {
        // The onboarding's categories wait in the outbox; the account's replace them.
        let store = FakeSyncStore(events: [event("groceries", name: "Mine")], counts: ["account": 0])
        let suite = suite()
        Self.serve(["account": [Self.row("a1")], "category": [Self.row("food")]])
        let outcome = try await engine(store, suite: suite).syncOnce(account: "u1")
        #expect(outcome == .synced)
        #expect(await store.replacedWith?.map(\.entity) == ["account", "category"])
        #expect(!paths().contains("/sync/push"))
        #expect(cursor(suite) == 7)
    }

    @Test
    func onlyThisDeviceHasDataSoItGoesUpAsBefore() async throws {
        let store = FakeSyncStore(events: [event("groceries", name: "Mine")], counts: ["transaction": 4])
        let suite = suite()
        // Categories and settings in the account aren't user data.
        Self.serve(["category": [Self.row("food", name: "Food")], "settings": [Self.row("settings")]])
        let outcome = try await engine(store, suite: suite).syncOnce(account: "u1")
        #expect(outcome == .synced)
        #expect(await store.replacedWith == nil)
        #expect(paths().contains("/sync/push"))
        #expect(await store.pendingCount() == 0)
        #expect(await store.appliedNames().contains("Food"))
        #expect(cursor(suite) == 7)
    }

    @Test
    func laterSyncsNeverAskAgain() async throws {
        let store = FakeSyncStore(counts: ["transaction": 4])
        let suite = suite()
        UserDefaults(suiteName: suite)?.set(3, forKey: "sync.cursor")
        Self.serve(["transaction": [Self.row("t1")]])
        let outcome = try await engine(store, suite: suite).syncOnce(account: "u1")
        #expect(outcome == .synced)
        #expect(!paths().contains("/sync/snapshot"))
    }

    @Test
    func anotherAccountStartsWithItsOwnFirstSync() async throws {
        let store = FakeSyncStore(counts: ["transaction": 4])
        let suite = suite()
        UserDefaults(suiteName: suite)?.set(3, forKey: "sync.cursor")
        UserDefaults(suiteName: suite)?.set("u1", forKey: "sync.account")
        Self.serve(["transaction": [Self.row("t1")]])
        let outcome = try await engine(store, suite: suite).syncOnce(account: "u2")
        #expect(outcome == .needsChoice(SyncConflict(device: SyncDataSummary(movements: 4), account: SyncDataSummary(movements: 1))))
    }

    @Test
    func usingTheAccountsDataReplacesThisDeviceAndSyncsOn() async throws {
        let store = FakeSyncStore(events: [event("groceries", name: "Mine")], counts: ["transaction": 4])
        let suite = suite()
        Self.serve(["transaction": [Self.row("t1")], "settings": [Self.row("settings")]])
        try await engine(store, suite: suite).resolve(.useAccount, account: "u1")
        #expect(await store.replacedWith?.map(\.entity) == ["settings", "transaction"])
        #expect(await store.uploadedOver == nil)
        #expect(cursor(suite) == 7)
        #expect(paths().last == "/sync/pull")
    }

    @Test
    func keepingThisDevicesDataSendsTheUploadAndThenSyncsOn() async throws {
        let store = FakeSyncStore(counts: ["transaction": 4])
        let suite = suite()
        Self.serve(["transaction": [Self.row("t1")], "account": [Self.row("a1")]])
        try await engine(store, suite: suite).resolve(.keepDevice, account: "u1")
        #expect(await store.uploadedOver?.count == 2)
        #expect(await store.replacedWith == nil)
        let push = try #require(StubProtocol.requests.first { $0.url?.path == "/sync/push" })
        let body = try #require(push.httpBody.flatMap { try JSONSerialization.jsonObject(with: $0) as? [String: Any] })
        let operations = (body["events"] as? [[String: Any]])?.compactMap { $0["operation"] as? String }
        #expect(operations == ["delete", "delete"])
        #expect(await store.pendingCount() == 0)
        #expect(cursor(suite) == 7)
    }

    /// The app quit halfway through bringing the account's data down: the next round finishes the
    /// download instead of finding data on both sides and asking.
    @Test
    func aDownloadCutShortFinishesWithoutAsking() async throws {
        let store = FakeSyncStore(counts: ["transaction": 2])
        let suite = suite()
        UserDefaults(suiteName: suite)?.set("useAccount", forKey: "sync.choosing")
        Self.serve(["transaction": [Self.row("t1"), Self.row("t2")]])
        let outcome = try await engine(store, suite: suite).syncOnce(account: "u1")
        #expect(outcome == .synced)
        #expect(await store.replacedWith?.count == 2)
        #expect(cursor(suite) == 7)
        #expect(UserDefaults(suiteName: suite)?.string(forKey: "sync.choosing") == nil)
    }

    @Test
    func resettingForgetsTheCursorSoTheNextSyncIsAFirstSyncAgain() async {
        let store = FakeSyncStore()
        let suite = suite()
        UserDefaults(suiteName: suite)?.set(3, forKey: "sync.cursor")
        let engine = engine(store, suite: suite)
        await engine.reset()
        #expect(cursor(suite) == nil)
    }
}
