import CloudAccountDomain
import Domain
import Foundation

/// iOS twin of keepwell-web's sync engine (ADR 0005 in keepwell-api): push the outbox, settle each
/// answer, then pull until caught up. A new installation loads a snapshot first.
public actor SyncEngine {
    static let entities = [
        "account", "card", "category", "transaction", "recurringRule", "savingsGoal", "loan", "loanPayment",
        "personalDebt", "personalDebtRepayment", "categorizationRule", "settings",
    ]

    private let client: APIClient
    private let store: any SyncStore
    private let defaults: UserDefaults
    private let clientID: String

    /// `defaultsSuite` keeps the cursor apart (tests); `nil` is the app's standard defaults.
    public init(client: APIClient, store: any SyncStore, defaultsSuite: String? = nil, clientID: String) {
        self.client = client
        self.store = store
        defaults = defaultsSuite.flatMap(UserDefaults.init(suiteName:)) ?? .standard
        self.clientID = clientID
    }

    private var cursor: Int? {
        get { defaults.object(forKey: "sync.cursor") as? Int }
        set { defaults.set(newValue, forKey: "sync.cursor") }
    }

    public var lastSync: Date? { defaults.object(forKey: "sync.lastAt") as? Date }

    public var rejected: [RejectedChange] {
        (defaults.data(forKey: "sync.rejected")).flatMap { try? JSONDecoder().decode([RejectedChange].self, from: $0) } ?? []
    }

    /// Forgets the cursor, so the next round starts from a snapshot (sign-out, another account).
    public func reset() {
        defaults.removeObject(forKey: "sync.cursor")
        defaults.removeObject(forKey: "sync.lastAt")
    }

    /// One round. Throws `CloudAccountError` as the API answered.
    public func syncOnce() async throws(CloudAccountError) {
        try await push()
        try await pull()
        defaults.set(Date.now, forKey: "sync.lastAt")
    }

    // MARK: - Push

    private struct PushBody: Encodable, Sendable {
        let client_id: String // swiftlint:disable:this identifier_name
        let platform = "ios"
        let events: [RawJSON]
    }

    private struct PushAnswer: Decodable {
        struct Result: Decodable {
            let event_id: String // swiftlint:disable:this identifier_name
            let status: String
            let reason: String?
            let updated_at: String? // swiftlint:disable:this identifier_name
            let current: RawJSON?
        }

        let results: [Result]
        let partial: Bool
    }

    private func push() async throws(CloudAccountError) {
        while true {
            let events = await (try? store.pendingEvents(limit: 200)) ?? []
            guard !events.isEmpty else { return }
            let body = PushBody(client_id: clientID, events: events.map(Self.envelope))
            let answer: PushAnswer = try await decode(client.send("POST", "sync/push", json: body))
            let byID = Dictionary(uniqueKeysWithValues: events.map { ($0.id.uuidString.lowercased(), $0) })
            var answered: [UUID] = []
            var refused: [RejectedChange] = []
            for result in answer.results {
                guard let event = byID[result.event_id] else { continue }
                answered.append(event.id)
                if result.status == "rejected" {
                    refused.append(RejectedChange(
                        entity: event.entity,
                        entityID: event.entityID,
                        reason: result.reason ?? "rejected",
                        at: .now,
                    ))
                }
            }
            // Every answered event leaves the outbox, rejected ones too: retrying them would block the rest.
            try? await store.removeEvents(ids: answered)
            await settle(answer.results, events: byID)
            if !refused.isEmpty {
                let kept = Array((refused + rejected).prefix(50))
                defaults.set(try? JSONEncoder().encode(kept), forKey: "sync.rejected")
            }
            if answer.partial || answer.results.count < events.count {
                return
            }
        }
    }

    /// Adopts what the server decided for each answered row, unless a newer local change waits.
    private func settle(_ results: [PushAnswer.Result], events byID: [String: OutboxEvent]) async {
        for result in results {
            guard let event = byID[result.event_id],
                  await !(store.hasPendingEvent(entity: event.entity, entityID: event.entityID)) else { continue }
            if let current = result.current {
                try? await store.applyRemote(entity: event.entity, row: current.data)
            } else if result.status == "applied", let text = result.updated_at, let date = Self.parseDate(text) {
                try? await store.adoptUpdatedAt(entity: event.entity, entityID: event.entityID, updatedAt: date)
            }
        }
    }

    // MARK: - Pull

    private struct PullAnswer: Decodable {
        struct Change: Decodable {
            let entity: String
            let entity_id: String // swiftlint:disable:this identifier_name
            let row: RawJSON
        }

        let changes: [Change]
        let next_cursor: Int // swiftlint:disable:this identifier_name
        let has_more: Bool // swiftlint:disable:this identifier_name
    }

    private struct SnapshotAnswer: Decodable {
        let rows: [RawJSON]
        let server_seq: Int // swiftlint:disable:this identifier_name
        let next_after: String? // swiftlint:disable:this identifier_name
    }

    private func pull() async throws(CloudAccountError) {
        if cursor == nil {
            var lowest = Int.max
            for entity in Self.entities {
                var after = ""
                while true {
                    let page: SnapshotAnswer = try await decode(client.send(
                        "GET",
                        "sync/snapshot",
                        query: ["entity": entity, "after": after, "limit": "500"],
                    ))
                    lowest = min(lowest, page.server_seq)
                    for row in page.rows {
                        try await adopt(entity: entity, row: row)
                    }
                    guard let next = page.next_after else { break }
                    after = next
                }
            }
            cursor = lowest == .max ? 0 : lowest
        }
        while true {
            let position = cursor ?? 0
            let page: PullAnswer = try await decode(client.send(
                "GET",
                "sync/pull",
                query: ["client_id": clientID, "cursor": String(position), "limit": "500"],
            ))
            for change in page.changes {
                try await adopt(entity: change.entity, row: change.row)
            }
            // Saved only after the page is applied: a crash midway pulls it again.
            cursor = page.next_cursor
            if !page.has_more {
                return
            }
        }
    }

    /// The server's row is the truth, except for a row with a pending local change.
    private func adopt(entity: String, row: RawJSON) async throws(CloudAccountError) {
        guard let id = row.object?["id"] as? String else { return }
        if await store.hasPendingEvent(entity: entity, entityID: id) {
            return
        }
        do {
            try await store.applyRemote(entity: entity, row: row.data)
        } catch {
            throw .server(code: "apply_failed", requestID: nil)
        }
    }

    // MARK: - Helpers

    private static func envelope(_ event: OutboxEvent) -> RawJSON {
        let payload = (try? JSONSerialization.jsonObject(with: event.payload)) ?? [:]
        let object: [String: Any] = [
            "event_id": event.id.uuidString.lowercased(), "entity": event.entity, "entity_id": event.entityID,
            "operation": event.operation, "payload": payload, "created_at": NameBasedID.isoMilliseconds(event.createdAt),
        ]
        return RawJSON(data: (try? JSONSerialization.data(withJSONObject: object)) ?? Data("{}".utf8))
    }

    static func parseDate(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: text)
    }

    private func decode<T: Decodable>(_ response: APIClient.Response) throws(CloudAccountError) -> T {
        switch response.status {
        case 200 ..< 300:
            do {
                return try JSONDecoder().decode(T.self, from: response.body)
            } catch {
                throw .server(code: "bad_response", requestID: nil)
            }
        case 401:
            throw .signedOut
        case 403:
            let code = (try? JSONSerialization.jsonObject(with: response.body) as? [String: Any])
                .flatMap { $0["error"] as? [String: Any] }?["code"] as? String
            throw code == "needs_plan" ? .needsPlan : .server(code: code ?? "forbidden", requestID: nil)
        default:
            throw .server(code: "http_\(response.status)", requestID: nil)
        }
    }
}

/// JSON passed through untouched (rows go to SwiftData as the server sent them).
public struct RawJSON: Codable, Sendable {
    public let data: Data

    public init(data: Data) {
        self.data = data
    }

    var object: [String: Any]? { try? JSONSerialization.jsonObject(with: data) as? [String: Any] }

    public init(from decoder: any Decoder) throws {
        let value = try decoder.singleValueContainer().decode(AnyCodable.self)
        data = try JSONSerialization.data(withJSONObject: value.value, options: [.fragmentsAllowed])
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(AnyCodable(JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])))
    }
}

/// Just enough to carry arbitrary JSON through Codable.
struct AnyCodable: Codable, @unchecked Sendable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([Self].self) {
            value = array.map(\.value)
        } else {
            value = try container.decode([String: Self].self).mapValues(\.value)
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case is NSNull: try container.encodeNil()
        case let number as NSNumber where CFGetTypeID(number) == CFBooleanGetTypeID(): try container.encode(number.boolValue)
        case let int as Int: try container.encode(int)
        case let double as Double: try container.encode(double)
        case let string as String: try container.encode(string)
        case let array as [Any]: try container.encode(array.map(Self.init))
        case let object as [String: Any]: try container.encode(object.mapValues(Self.init))
        default: try container.encodeNil()
        }
    }
}
