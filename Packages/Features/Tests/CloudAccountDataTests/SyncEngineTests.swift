import CloudAccountData
import CloudAccountDomain
import Domain
import Foundation
import Testing

@Suite("iOS sync engine", .serialized)
struct SyncEngineTests {
    let base = URL(string: "https://api.example.com") ?? URL(fileURLWithPath: "/")

    func engine(
        _ store: FakeSyncStore,
        suite: String,
        build: String = "1",
        repair: (any ReassignDeletedCategoriesUseCase)? = nil,
        merchantLinksResynced: Bool = true,
    ) -> SyncEngine {
        // Most tests are about a device past the one-time merchant download; its own tests turn it off.
        if merchantLinksResynced {
            UserDefaults(suiteName: suite)?.set(true, forKey: "sync.merchantLinksResynced")
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        StubProtocol.requests = []
        let client = APIClient(
            baseURL: base,
            store: InMemorySessionStore(cookie: "better-auth.session_token=x"),
            configuration: configuration,
        )
        return SyncEngine(
            client: client,
            store: store,
            defaultsSuite: suite,
            clientID: "client-1",
            appBuild: build,
            repairCategories: repair,
        )
    }

    func suite() -> String {
        "sync-tests-\(UUID().uuidString)"
    }

    func cursor(_ suite: String) -> Int? {
        UserDefaults(suiteName: suite)?.object(forKey: "sync.cursor") as? Int
    }

    func event(_ id: String, name: String) -> OutboxEvent {
        let row: [String: Any] = ["id": id, "name": name, "updated_at": "2026-11-01T10:00:00.000Z", "deleted_at": NSNull()]
        return OutboxEvent(
            id: UUID(),
            entity: "category",
            entityID: id,
            operation: "update",
            payload: (try? JSONSerialization.data(withJSONObject: row)) ?? Data(),
            createdAt: .now,
        )
    }

    static func json(_ object: Any) -> Data {
        (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
    }

    @Test
    func pushesEmptiesTheOutboxAdoptsTheWinnerAndPullsTheRest() async throws {
        let mine = event("groceries", name: "Mine")
        let store = FakeSyncStore(events: [mine])
        let suite = suite()
        UserDefaults(suiteName: suite)?.set(5, forKey: "sync.cursor")
        StubProtocol.handler = { request in
            switch request.url?.path {
            case "/sync/push":
                let current: [String: Any] = [
                    "id": "groceries",
                    "name": "Winner",
                    "updated_at": "2026-11-02T00:00:00.000Z",
                    "deleted_at": NSNull(),
                ]
                return (
                    200,
                    [:],
                    Self.json([
                        "results": [["event_id": mine.id.uuidString.lowercased(), "status": "stale", "current": current]],
                        "partial": false,
                    ]),
                )
            case "/sync/pull":
                let row: [String: Any] = [
                    "id": "rent",
                    "name": "From the web",
                    "updated_at": "2026-11-03T00:00:00.000Z",
                    "deleted_at": NSNull(),
                ]
                return (
                    200,
                    [:],
                    Self.json([
                        "changes": [["server_seq": 6, "entity": "category", "entity_id": "rent", "operation": "create", "row": row]],
                        "next_cursor": 6,
                        "has_more": false,
                    ]),
                )
            default:
                return (404, [:], Data())
            }
        }
        try await engine(store, suite: suite).syncOnce()
        #expect(await store.pendingCount() == 0)
        #expect(await store.appliedNames() == ["Winner", "From the web"])
        #expect(cursor(suite) == 6)
        let pull = try #require(StubProtocol.requests.last?.url?.query)
        #expect(pull.contains("cursor=5"))
    }

    @Test
    func aNewInstallationLoadsSnapshotsFirst() async throws {
        let store = FakeSyncStore()
        let suite = suite()
        StubProtocol.handler = { request in
            if request.url?.path == "/sync/snapshot" {
                let query = request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?.queryItems ?? []
                let entity = query.first { $0.name == "entity" }?.value
                let rows: [[String: Any]] = entity == "category" ? [[
                    "id": "groceries",
                    "name": "Super",
                    "updated_at": "2026-11-01T00:00:00.000Z",
                    "deleted_at": NSNull(),
                ]] : []
                return (200, [:], Self.json(["rows": rows, "server_seq": 9, "next_after": NSNull()]))
            }
            return (200, [:], Self.json(["changes": [], "next_cursor": 9, "has_more": false]))
        }
        try await engine(store, suite: suite).syncOnce()
        #expect(await store.appliedNames() == ["Super"])
        #expect(cursor(suite) == 9)
    }

    @Test
    func neverOverwritesARowWithAPendingChange() async throws {
        let store = FakeSyncStore()
        let suite = suite()
        UserDefaults(suiteName: suite)?.set(0, forKey: "sync.cursor")
        StubProtocol.handler = { request in
            if request.url?.path == "/sync/push" {
                return (200, [:], Self.json(["results": [], "partial": false]))
            }
            let row: [String: Any] = ["id": "groceries", "name": "Theirs", "updated_at": "2026-11-01T00:00:00.000Z", "deleted_at": NSNull()]
            return (
                200,
                [:],
                Self.json([
                    "changes": [["server_seq": 1, "entity": "category", "entity_id": "groceries", "operation": "update", "row": row]],
                    "next_cursor": 1,
                    "has_more": false,
                ]),
            )
        }
        await store.push(event("groceries", name: "Mine"))
        try await engine(store, suite: suite).syncOnce()
        #expect(await store.appliedCount() == 0)
    }

    @Test
    func stopsWithNeedsPlanWhenTheAccountLacksSync() async {
        StubProtocol.handler = { _ in (403, [:], Self.json(["error": ["code": "needs_plan", "message": "x"], "request_id": "r"])) }
        let store = FakeSyncStore(events: [event("groceries", name: "Mine")])
        await #expect(throws: CloudAccountError.needsPlan) {
            try await engine(store, suite: suite()).syncOnce()
        }
        #expect(await store.pendingCount() == 1)
    }

    // MARK: - Rows this version can't store

    static func category(_ id: String, name: String) -> [String: Any] {
        ["id": id, "name": name, "updated_at": "2026-11-03T00:00:00.000Z", "deleted_at": NSNull()]
    }

    /// A pull page of three categories, the middle one unreadable here; snapshots hold the same rows.
    static func serveThreeCategories(_ request: URLRequest) -> (Int, [String: String], Data) {
        let rows = [category("first", name: "First"), category("newer", name: "Newer"), category("last", name: "Last")]
        switch request.url?.path {
        case "/sync/pull":
            let changes = rows.enumerated().map { index, row in
                ["server_seq": index + 1, "entity": "category", "entity_id": row["id"] ?? "", "operation": "create", "row": row]
            }
            return (200, [:], json(["changes": changes, "next_cursor": 3, "has_more": false]))
        case "/sync/snapshot":
            return (200, [:], json(["rows": rows, "server_seq": 3, "next_after": NSNull()]))
        default:
            return (404, [:], Data())
        }
    }

    @Test
    func aRowThatCantBeStoredIsSkippedAndRecordedAndTheCursorMovesOn() async throws {
        let store = FakeSyncStore()
        await store.setUnreadable(["newer"])
        let suite = suite()
        UserDefaults(suiteName: suite)?.set(0, forKey: "sync.cursor")
        StubProtocol.handler = Self.serveThreeCategories
        let engine = engine(store, suite: suite)

        try await engine.syncOnce()

        #expect(await store.appliedNames() == ["First", "Last"])
        #expect(cursor(suite) == 3)
        let skipped = await engine.skipped
        #expect(skipped.map(\.entity) == ["category"])
        #expect(skipped.map(\.entityID) == ["newer"])
        #expect(skipped.map(\.reason) == ["corruptedData: wire amount"])
    }

    @Test
    func aStoreThatCantWriteStopsThePullWithoutMovingTheCursor() async {
        let store = FakeSyncStore()
        await store.setFailsToStore(true)
        let suite = suite()
        UserDefaults(suiteName: suite)?.set(0, forKey: "sync.cursor")
        StubProtocol.handler = Self.serveThreeCategories
        let engine = engine(store, suite: suite)

        await #expect(throws: CloudAccountError.server(code: "apply_failed", requestID: nil)) {
            try await engine.syncOnce()
        }
        #expect(cursor(suite) == 0)
        #expect(await engine.skipped.isEmpty)
    }

    @Test
    func anUpdatedAppDownloadsTheSkippedEntityAgainOnce() async throws {
        let store = FakeSyncStore()
        await store.setUnreadable(["newer"])
        let suite = suite()
        UserDefaults(suiteName: suite)?.set(0, forKey: "sync.cursor")
        StubProtocol.handler = Self.serveThreeCategories
        try await engine(store, suite: suite, build: "1").syncOnce()

        // The same build doesn't try again: it would skip the row again.
        let sameBuild = engine(store, suite: suite, build: "1")
        try await sameBuild.syncOnce()
        #expect(!StubProtocol.requests.contains { $0.url?.path == "/sync/snapshot" })
        #expect(await sameBuild.skipped.count == 1)

        await store.setUnreadable([])
        let updated = engine(store, suite: suite, build: "2")
        try await updated.syncOnce()
        let snapshots = StubProtocol.requests.filter { $0.url?.path == "/sync/snapshot" }
        #expect(snapshots.count == 1)
        #expect(snapshots.first?.url?.query?.contains("entity=category") == true)
        #expect(await store.appliedNames().contains("Newer"))
        #expect(await updated.skipped.isEmpty)

        let again = engine(store, suite: suite, build: "2")
        try await again.syncOnce()
        #expect(!StubProtocol.requests.contains { $0.url?.path == "/sync/snapshot" })
    }

    @Test
    func aRowStillUnreadableAfterTheUpdateWaitsForTheNextOne() async throws {
        let store = FakeSyncStore()
        await store.setUnreadable(["newer"])
        let suite = suite()
        UserDefaults(suiteName: suite)?.set(0, forKey: "sync.cursor")
        StubProtocol.handler = Self.serveThreeCategories
        try await engine(store, suite: suite, build: "1").syncOnce()

        let updated = engine(store, suite: suite, build: "2")
        try await updated.syncOnce()
        #expect(await updated.skipped.map(\.entityID) == ["newer"])

        let sameBuild = engine(store, suite: suite, build: "2")
        try await sameBuild.syncOnce()
        #expect(!StubProtocol.requests.contains { $0.url?.path == "/sync/snapshot" })
    }

    @Test
    func theRecordedReasonNeverCarriesTheRowsValues() async throws {
        let store = FakeSyncStore()
        await store.setUnreadable(["newer"], as: .corruptedData("Money entry 120.50 USD"))
        let suite = suite()
        UserDefaults(suiteName: suite)?.set(0, forKey: "sync.cursor")
        StubProtocol.handler = Self.serveThreeCategories
        let engine = engine(store, suite: suite)

        try await engine.syncOnce()

        #expect(await engine.skipped.map(\.reason) == ["corruptedData"])
    }
}

// MARK: - Category repair

extension SyncEngineTests {
    @Test
    func afterThePullTheRepairGetsTheCategoryTombstones() async throws {
        let store = FakeSyncStore()
        await store.setDeletedCategories(["custom-boat"])
        let suite = suite()
        UserDefaults(suiteName: suite)?.set(0, forKey: "sync.cursor")
        StubProtocol.handler = { _ in
            (200, [:], Self.json(["changes": [], "next_cursor": 0, "has_more": false]))
        }
        let repair = SpyRepair()
        try await engine(store, suite: suite, repair: repair).syncOnce()
        #expect(await repair.calls == [["custom-boat"]])
    }
}

/// Records what the engine hands the repair after a pull.
actor SpyRepair: ReassignDeletedCategoriesUseCase {
    private(set) var calls: [Set<String>] = []

    func execute(deletedCategoryIDs: Set<String>) throws(DomainError) -> Int {
        calls.append(deletedCategoryIDs)
        return 0
    }
}
