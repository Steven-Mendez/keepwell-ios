import CloudAccountDomain
import Domain
import Foundation
import os

/// iOS twin of keepwell-web's sync engine (ADR 0005 in keepwell-api): push the outbox, settle each
/// answer, then pull until caught up. The first sync with an account loads a snapshot first, and
/// when this device and the account both hold data it stops for the person to keep one side.
///
/// Things worth knowing when changing it:
/// - Nothing local is cleared before the account's whole snapshot is fetched, and clearing and
///   applying it is one save. A first sync cut short leaves no choice behind to resume: it asks again.
/// - An id the account already deleted can't be revived by "Keep this iPhone's data": the server
///   keeps its tombstone, so the row stays deleted.
/// - Switching accounts on one device treats unsent changes as this device's data: with an account
///   that has data the person is asked which to keep; with an empty one this device's rows upload.
/// - A row the store can't read (one written by a newer version, say) is skipped and recorded, so
///   one row never holds back the rest of the account. Its entity is downloaded again after the
///   app is updated.
public actor SyncEngine { // swiftlint:disable:this type_body_length
    /// Settings come first: a download cut short still has the account's currencies.
    static let entities = [
        "settings", "account", "card", "category", "transaction", "recurringRule", "savingsGoal", "loan", "loanPayment",
        "personalDebt", "personalDebtRepayment", "categorizationRule", "notificationState", "merchant",
    ]

    private static let legacyChoiceKey = "sync.choosing"

    private let client: APIClient
    let store: any SyncConflictStore
    private let defaults: UserDefaults
    private let clientID: String
    private let appBuild: String
    let repairCategories: (any ReassignDeletedCategoriesUseCase)?
    let repairMerchants: (any UnlinkDeletedMerchantsUseCase)?
    let fillTimeZone: (any FillHomeTimeZoneUseCase)?

    /// `defaultsSuite` keeps the cursor apart (tests); `nil` is the app's standard defaults.
    /// `appBuild` tells an updated app, which may read rows this one skipped.
    /// `repairCategories` and `repairMerchants` run after every pull (keepwell-web does the same), and `fillTimeZone`
    /// after a round, once the account's settings are here.
    public init(
        client: APIClient,
        store: any SyncConflictStore,
        defaultsSuite: String? = nil,
        clientID: String,
        appBuild: String = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "",
        repairCategories: (any ReassignDeletedCategoriesUseCase)? = nil,
        repairMerchants: (any UnlinkDeletedMerchantsUseCase)? = nil,
        fillTimeZone: (any FillHomeTimeZoneUseCase)? = nil,
    ) {
        self.client = client
        self.store = store
        defaults = defaultsSuite.flatMap(UserDefaults.init(suiteName:)) ?? .standard
        self.clientID = clientID
        self.appBuild = appBuild
        self.repairCategories = repairCategories
        self.repairMerchants = repairMerchants
        self.fillTimeZone = fillTimeZone
    }

    private var cursor: Int? {
        get { defaults.object(forKey: "sync.cursor") as? Int }
        set { defaults.set(newValue, forKey: "sync.cursor") }
    }

    /// The account the cursor belongs to.
    private var cursorAccount: String? {
        get { defaults.string(forKey: "sync.account") }
        set { defaults.set(newValue, forKey: "sync.account") }
    }

    public var lastSync: Date? { defaults.object(forKey: "sync.lastAt") as? Date }

    public var rejected: [RejectedChange] {
        (defaults.data(forKey: "sync.rejected")).flatMap { try? JSONDecoder().decode([RejectedChange].self, from: $0) } ?? []
    }

    /// Rows from the server that this version couldn't store, newest first (at most 50).
    public var skipped: [SkippedRow] {
        (defaults.data(forKey: Self.skippedKey)).flatMap { try? JSONDecoder().decode([SkippedRow].self, from: $0) } ?? []
    }

    /// Forgets the cursor, so the next round starts from a snapshot (sign-out, another account).
    public func reset() {
        defaults.removeObject(forKey: "sync.cursor")
        defaults.removeObject(forKey: "sync.lastAt")
        defaults.removeObject(forKey: "sync.rejected")
        defaults.removeObject(forKey: Self.skippedKey)
        defaults.removeObject(forKey: Self.retryEntitiesKey)
        defaults.removeObject(forKey: Self.retryBuildKey)
        defaults.removeObject(forKey: Self.legacyChoiceKey)
        defaults.removeObject(forKey: "sync.account")
    }

    /// One round. Throws `CloudAccountError` as the API answered. `account` is the signed-in
    /// account's id; the first round with it decides how the two sides meet.
    @discardableResult
    public func syncOnce(account: String? = nil) async throws(CloudAccountError) -> SyncRoundOutcome {
        bind(to: account)
        if cursor == nil {
            // Older versions recorded a choice under way and finished it on the next round, which
            // could clear data entered since. Nothing resumes now: a first sync cut short finds
            // what it brought down here and asks.
            defaults.removeObject(forKey: Self.legacyChoiceKey)
            let snapshot = try await fetchSnapshot()
            let device = try await deviceSummary()
            let remote = Self.summary(of: snapshot.rows)
            switch (device.hasUserData, remote.hasUserData) {
            case (true, true):
                // Nothing goes up or comes down until the person keeps one side.
                return .needsChoice(SyncConflict(device: device, account: remote))
            case (false, true):
                // Only the account has data: it comes down whole, the onboarding's categories and
                // settings included, and nothing of this device's goes up over it. No choice is
                // recorded: the snapshot is in hand and the replace is one save, so a failure
                // changes nothing and the next round looks at both sides again.
                try await replaceLocal(with: snapshot.rows)
            case (true, false):
                // The account has nothing (a new one, or switched to from another whose outbox was
                // already sent): this device's rows would never go up, as nothing is queued for
                // them. Its own settings win, as `adopt` skips rows with a pending event.
                do {
                    try await store.queueFullUpload(replacing: [], at: .now)
                } catch {
                    throw .server(code: "local_write_failed", requestID: nil)
                }
                try await adoptAll(snapshot.rows)
            case (false, false):
                try await adoptAll(snapshot.rows)
            }
            cursor = snapshot.cursor
        }
        try await push()
        try await retrySkipped()
        try await pull()
        if try await fillHomeTimeZone() {
            try await push()
        }
        defaults.set(Date.now, forKey: "sync.lastAt")
        return .synced
    }

    /// Ends a conflict by keeping one side, then syncs normally. The account's rows are read again
    /// here: another device may have changed them while the choice waited.
    public func resolve(_ choice: SyncChoice, account: String? = nil) async throws(CloudAccountError) {
        bind(to: account)
        // The account's rows come first: when they can't be fetched nothing local has changed and
        // no choice is recorded, so the person is asked again with whatever they entered since.
        let snapshot = try await fetchSnapshot()
        switch choice {
        case .useAccount:
            try await replaceLocal(with: snapshot.rows)
        case .keepDevice:
            do {
                try await store.queueFullUpload(replacing: snapshot.rows, at: .now)
            } catch {
                throw .server(code: "local_write_failed", requestID: nil)
            }
        }
        // Saved once the outbox holds the whole upload (or the account's data is down): a round
        // cut short sends the rest later instead of asking again.
        cursor = snapshot.cursor
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
            let answer: PushAnswer = try await Self.decode(client.send("POST", "sync/push", json: body))
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
                _ = try? await store.applyRemote(entity: event.entity, row: current.data)
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
        while true {
            let position = cursor ?? 0
            let page: PullAnswer = try await Self.decode(client.send(
                "GET",
                "sync/pull",
                query: ["client_id": clientID, "cursor": String(position), "limit": "500"],
            ))
            for change in page.changes {
                try await adopt(entity: change.entity, row: change.row)
            }
            // Saved only after the page is applied: a crash midway pulls it again. A skipped row
            // doesn't hold it back: it is recorded and retried after an update.
            cursor = page.next_cursor
            if !page.has_more {
                break
            }
        }
        try await repairDeletedCategories()
        try await repairDeletedMerchants()
    }

    /// The server's row is the truth, except for a row with a pending local change.
    private func adopt(entity: String, row: RawJSON) async throws(CloudAccountError) {
        try await adopt(entity: entity, data: row.data)
    }

    /// `true` when the row couldn't be stored and was skipped.
    @discardableResult
    private func adopt(entity: String, data: Data) async throws(CloudAccountError) -> Bool {
        guard let id = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["id"] as? String else { return false }
        if await store.hasPendingEvent(entity: entity, entityID: id) {
            return false
        }
        do {
            try await store.applyRemote(entity: entity, row: data)
            return false
        } catch {
            // The store itself couldn't write: nothing says this row is the problem, so the page
            // is pulled again rather than the row lost until an update.
            if case .persistence = error {
                throw .server(code: "apply_failed", requestID: nil)
            }
            recordSkipped(entity: entity, id: id, error: error)
            return true
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

    private nonisolated static func decode<T: Decodable>(_ response: APIClient.Response) throws(CloudAccountError) -> T {
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

// MARK: - First sync

extension SyncEngine {
    /// Entities fetched at once. URLSession opens at most 6 connections per host (and HTTP/2
    /// multiplexes them anyway), so more would only queue.
    public static let snapshotConcurrency = 6

    /// Every row the account holds, tombstones included, and the cursor that follows them. The
    /// entities download concurrently (each one pages in order), but the rows come back in
    /// `entities` order whatever finishes first, so settings still apply first. One failure fails
    /// the whole fetch and cancels the rest: nothing is applied from a partial snapshot.
    private func fetchSnapshot() async throws(CloudAccountError) -> (rows: [RemoteRow], cursor: Int) {
        let entities = Self.entities
        let client = client
        var fetched = [[RemoteRow]](repeating: [], count: entities.count)
        var lowest = Int.max
        do {
            try await withThrowingTaskGroup(of: (index: Int, rows: [RemoteRow], seq: Int).self) { group in
                for (index, entity) in entities.enumerated() {
                    if index >= Self.snapshotConcurrency, let done = try await group.next() {
                        fetched[done.index] = done.rows
                        lowest = min(lowest, done.seq)
                    }
                    group.addTask {
                        let result = try await Self.fetchEntity(entity, client: client)
                        return (index, result.rows, result.seq)
                    }
                }
                for try await done in group {
                    fetched[done.index] = done.rows
                    lowest = min(lowest, done.seq)
                }
            }
        } catch let error as CloudAccountError {
            throw error
        } catch {
            throw .unreachable
        }
        return (fetched.flatMap(\.self), lowest == .max ? 0 : lowest)
    }

    private static func fetchEntity(_ entity: String, client: APIClient) async throws(CloudAccountError) -> (rows: [RemoteRow], seq: Int) {
        var lowest = Int.max
        var rows: [RemoteRow] = []
        var after = ""
        while true {
            let page: SnapshotAnswer = try await decode(client.send(
                "GET",
                "sync/snapshot",
                query: ["entity": entity, "after": after, "limit": "500"],
            ))
            lowest = min(lowest, page.server_seq)
            rows += page.rows.map { RemoteRow(entity: entity, row: $0.data) }
            guard let next = page.next_after else { break }
            after = next
        }
        return (rows, lowest)
    }

    /// A cursor only means something for the account that made it: signing in to another account
    /// starts over with that account's first sync. A cursor from before accounts were recorded is
    /// taken to be the current account's, as it was.
    private func bind(to account: String?) {
        guard let account else { return }
        if let previous = cursorAccount, previous != account {
            reset()
        }
        cursorAccount = account
    }

    private func deviceSummary() async throws(CloudAccountError) -> SyncDataSummary {
        do {
            return try await SyncDataSummary(counts: store.localRowCounts())
        } catch {
            // Taking an unreadable store for an empty one could replace it; better to try again.
            throw .server(code: "local_read_failed", requestID: nil)
        }
    }

    /// Clears and applies the account's rows in one save, the snapshot already in hand. A row that
    /// can't be stored fails the whole replace with nothing changed (and no cursor), so it is tried
    /// again instead of being missing for good.
    private func replaceLocal(with rows: [RemoteRow]) async throws(CloudAccountError) {
        do {
            try await store.replaceSyncedData(with: rows)
        } catch {
            throw .server(code: "apply_failed", requestID: nil)
        }
    }

    private func adoptAll(_ rows: [RemoteRow]) async throws(CloudAccountError) {
        for remoteRow in rows {
            try await adopt(entity: remoteRow.entity, data: remoteRow.row)
        }
    }

    static func summary(of rows: [RemoteRow]) -> SyncDataSummary {
        var counts: [String: Int] = [:]
        for remoteRow in rows where SyncDataSummary.userDataEntities.contains(remoteRow.entity) {
            let object = try? JSONSerialization.jsonObject(with: remoteRow.row) as? [String: Any]
            let deleted = object?["deleted_at"].map { !($0 is NSNull) } ?? false
            if object != nil, !deleted {
                counts[remoteRow.entity, default: 0] += 1
            }
        }
        return SyncDataSummary(counts: counts)
    }
}

// MARK: - Skipped rows

extension SyncEngine {
    fileprivate static let skippedKey = "sync.skipped"
    /// Entities with a skipped row still to retry, and the build that skipped the oldest of them.
    fileprivate static let retryEntitiesKey = "sync.skippedEntities"
    fileprivate static let retryBuildKey = "sync.skippedBuild"
    fileprivate static let logger = Logger(subsystem: "CloudAccount", category: "Sync")

    private var retryEntities: Set<String> {
        Set(defaults.stringArray(forKey: Self.retryEntitiesKey) ?? [])
    }

    /// Logged and kept by entity and id only: the row's values never leave it.
    private func recordSkipped(entity: String, id: String, error: DomainError) {
        let reason = Self.reason(for: error)
        Self.logger.error("Skipped \(entity, privacy: .public) \(id, privacy: .public): \(reason, privacy: .public)")
        let entry = SkippedRow(entity: entity, entityID: id, reason: reason, at: .now)
        let others = skipped.filter { $0.entity != entity || $0.entityID != id }
        defaults.set(try? JSONEncoder().encode(Array(([entry] + others).prefix(50))), forKey: Self.skippedKey)
        var entities = retryEntities
        if entities.isEmpty {
            defaults.set(appBuild, forKey: Self.retryBuildKey)
        }
        entities.insert(entity)
        defaults.set(entities.sorted(), forKey: Self.retryEntitiesKey)
    }

    /// After an update, the entities that had skipped rows come down again whole: the server's rows
    /// are the truth (rows with a pending change are left alone as ever), so this is the same as
    /// pulling them again, and no row's data has to be kept on the side meanwhile. Nothing happens
    /// on the build that skipped them, and a download that fails is tried on the next round.
    private func retrySkipped() async throws(CloudAccountError) {
        let entities = retryEntities
        let build = defaults.string(forKey: Self.retryBuildKey)
        guard !entities.isEmpty, build != appBuild else { return }
        var rows: [RemoteRow] = []
        for entity in Self.entities where entities.contains(entity) {
            guard let fetched = try? await Self.fetchEntity(entity, client: client) else { return }
            rows += fetched.rows
        }
        defaults.set(
            try? JSONEncoder().encode(skipped.filter { !entities.contains($0.entity) }),
            forKey: Self.skippedKey,
        )
        defaults.removeObject(forKey: Self.retryEntitiesKey)
        defaults.removeObject(forKey: Self.retryBuildKey)
        do {
            try await adoptAll(rows)
        } catch {
            // Not all were tried: the next round tries them all again.
            defaults.set(retryEntities.union(entities).sorted(), forKey: Self.retryEntitiesKey)
            defaults.set(build, forKey: Self.retryBuildKey)
            throw error
        }
    }
}
