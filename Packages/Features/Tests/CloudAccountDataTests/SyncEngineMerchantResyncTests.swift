import CloudAccountData
import CloudAccountDomain
import Domain
import Foundation
import Testing

/// After upgrading from a build older than merchants: merchants and the rows with links come down
/// again once, before anything is pushed.
extension SyncEngineTests {
    private static let resyncKey = "sync.merchantLinksResynced"

    private static func linkedRow(_ id: String, merchant: String? = "m1") -> [String: Any] {
        [
            "id": id, "merchant_id": merchant ?? NSNull(), "via_merchant_id": NSNull(),
            "created_at": "2026-11-01T00:00:00.000Z", "updated_at": "2026-11-01T00:00:00.000Z", "deleted_at": NSNull(),
        ]
    }

    /// Snapshots per entity (failing while `snapshotsFail`), pushes answered as applied, empty pulls.
    private static func serveAccount(snapshotsFail: Bool = false) {
        let rows: [String: [[String: Any]]] = [
            "merchant": [["id": "m1", "name": "Subway", "is_platform": false]],
            "transaction": [linkedRow("pending-movement"), linkedRow("synced-movement")],
            "recurringRule": [linkedRow("rule")],
            "categorizationRule": [linkedRow("cat-rule")],
        ]
        StubProtocol.handler = { request in
            switch request.url?.path {
            case "/sync/snapshot":
                if snapshotsFail {
                    return (500, [:], Data())
                }
                let query = request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?.queryItems ?? []
                let entity = query.first { $0.name == "entity" }?.value ?? ""
                return (200, [:], json(["rows": rows[entity] ?? [], "server_seq": 9, "next_after": NSNull()]))
            case "/sync/push":
                let sent = StubProtocol.requests.last?.httpBody ?? request.httpBody
                let body = sent.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
                let events = body?["events"] as? [[String: Any]] ?? []
                let results = events.map { ["event_id": $0["event_id"] ?? "", "status": "applied"] }
                return (200, [:], json(["results": results, "partial": false]))
            default:
                return (200, [:], json(["changes": [], "next_cursor": 9, "has_more": false]))
            }
        }
    }

    private func pendingMovement() -> OutboxEvent {
        OutboxEvent(
            id: UUID(), entity: "transaction", entityID: "pending-movement", operation: "update",
            payload: Self.json(Self.linkedRow("pending-movement", merchant: nil)), createdAt: .now,
        )
    }

    private func resynced(_ suite: String) -> Bool {
        UserDefaults(suiteName: suite)?.bool(forKey: Self.resyncKey) ?? false
    }

    @Test
    func anUpgradedDeviceDownloadsMerchantsAndLinksBeforeItPushes() async throws {
        let store = FakeSyncStore(events: [pendingMovement()])
        let suite = suite()
        UserDefaults(suiteName: suite)?.set(5, forKey: "sync.cursor")
        Self.serveAccount()

        try await engine(store, suite: suite, merchantLinksResynced: false).syncOnce()

        let paths = StubProtocol.requests.compactMap(\.url?.path)
        let firstPush = try #require(paths.firstIndex(of: "/sync/push"))
        #expect(paths.prefix(firstPush).filter { $0 == "/sync/snapshot" }.count == 4)
        let entities = StubProtocol.requests.filter { $0.url?.path == "/sync/snapshot" }.compactMap {
            $0.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?.queryItems?.first { $0.name == "entity" }?.value
        }
        #expect(entities == ["merchant", "transaction", "recurringRule", "categorizationRule"])
        // Rows without a pending change are the server's; the pending one keeps its change and
        // only gets its links filled.
        #expect(await store.appliedRows() == [
            "merchant/m1", "transaction/synced-movement", "recurringRule/rule", "categorizationRule/cat-rule",
        ])
        #expect(await store.filledRows() == ["transaction/pending-movement"])
        #expect(await store.pendingCount() == 0)
        #expect(resynced(suite))
        #expect(cursor(suite) == 9)

        // Once only.
        try await engine(store, suite: suite, merchantLinksResynced: false).syncOnce()
        #expect(!StubProtocol.requests.contains { $0.url?.path == "/sync/snapshot" })
    }

    @Test
    func nothingIsPushedUntilTheDownloadSucceeds() async throws {
        let store = FakeSyncStore(events: [pendingMovement()])
        let suite = suite()
        UserDefaults(suiteName: suite)?.set(5, forKey: "sync.cursor")
        Self.serveAccount(snapshotsFail: true)

        await #expect(throws: CloudAccountError.self) {
            try await engine(store, suite: suite, merchantLinksResynced: false).syncOnce()
        }
        #expect(!StubProtocol.requests.contains { $0.url?.path == "/sync/push" })
        #expect(await store.pendingCount() == 1)
        #expect(await store.appliedCount() == 0)
        #expect(!resynced(suite))
        #expect(cursor(suite) == 5)

        Self.serveAccount()
        try await engine(store, suite: suite, merchantLinksResynced: false).syncOnce()
        #expect(StubProtocol.requests.contains { $0.url?.path == "/sync/push" })
        #expect(await store.pendingCount() == 0)
        #expect(resynced(suite))
    }

    @Test
    func aFirstSyncsSnapshotCountsAsTheDownload() async throws {
        let store = FakeSyncStore()
        let suite = suite()
        Self.serveAccount()

        try await engine(store, suite: suite, merchantLinksResynced: false).syncOnce(account: "u1")

        // One snapshot per entity, none of them twice.
        let snapshots = StubProtocol.requests.filter { $0.url?.path == "/sync/snapshot" }.compactMap(\.url?.query)
        #expect(snapshots.count == Set(snapshots).count)
        #expect(resynced(suite))
        #expect(await store.filledRows().isEmpty)
    }

    @Test
    func signingOutForgetsTheDownloadSoTheNextAccountsSnapshotDecides() async {
        let suite = suite()
        let engine = engine(FakeSyncStore(), suite: suite)
        #expect(resynced(suite))
        await engine.reset()
        #expect(!resynced(suite))
    }
}
