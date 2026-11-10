import CloudAccountData
import CloudAccountDomain
import Domain
import Foundation
import Testing

/// Local storage stand-in: records what the engine asks of it.
private actor FakeStore: SyncStore {
    var events: [OutboxEvent] = []
    var applied: [(String, [String: Any])] = []
    var adopted: [(String, Date)] = []

    init(events: [OutboxEvent] = []) {
        self.events = events
    }

    func pendingEvents(limit: Int) throws(DomainError) -> [OutboxEvent] {
        Array(events.prefix(limit))
    }

    func removeEvents(ids: [UUID]) throws(DomainError) {
        events.removeAll { ids.contains($0.id) }
    }

    func pendingCount() -> Int {
        events.count
    }

    func hasPendingEvent(entity: String, entityID: String) -> Bool {
        events.contains { $0.entity == entity && $0.entityID == entityID }
    }

    func applyRemote(entity: String, row: Data) throws(DomainError) -> Bool {
        applied.append((entity, (try? JSONSerialization.jsonObject(with: row) as? [String: Any]) ?? [:]))
        return true
    }

    func adoptUpdatedAt(entity: String, entityID _: String, updatedAt: Date) throws(DomainError) {
        adopted.append((entity, updatedAt))
    }

    func appliedNames() -> [String] {
        applied.compactMap { $0.1["name"] as? String }
    }

    func appliedCount() -> Int {
        applied.count
    }

    func push(_ event: OutboxEvent) {
        events.append(event)
    }
}

@Suite("iOS sync engine", .serialized)
struct SyncEngineTests {
    private let base = URL(string: "https://api.example.com") ?? URL(fileURLWithPath: "/")

    private func engine(_ store: FakeStore, suite: String) -> SyncEngine {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        StubProtocol.requests = []
        let client = APIClient(
            baseURL: base,
            store: InMemorySessionStore(cookie: "better-auth.session_token=x"),
            configuration: configuration,
        )
        return SyncEngine(client: client, store: store, defaultsSuite: suite, clientID: "client-1")
    }

    private func suite() -> String {
        "sync-tests-\(UUID().uuidString)"
    }

    private func cursor(_ suite: String) -> Int? {
        UserDefaults(suiteName: suite)?.object(forKey: "sync.cursor") as? Int
    }

    private func event(_ id: String, name: String) -> OutboxEvent {
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

    private static func json(_ object: Any) -> Data {
        (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
    }

    @Test
    func pushesEmptiesTheOutboxAdoptsTheWinnerAndPullsTheRest() async throws {
        let mine = event("groceries", name: "Mine")
        let store = FakeStore(events: [mine])
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
        let store = FakeStore()
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
        let store = FakeStore()
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
        let store = FakeStore(events: [event("groceries", name: "Mine")])
        await #expect(throws: CloudAccountError.needsPlan) {
            try await engine(store, suite: suite()).syncOnce()
        }
        #expect(await store.pendingCount() == 1)
    }
}
