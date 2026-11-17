import Domain
import DomainSamples
import Foundation
import SwiftData
import Testing
@testable import Persistence

/// The app reloads the screen in front when `ModelContext.didSave` arrives. A sync round writes
/// through the store's own actor, not the main context, so this checks that those saves announce
/// themselves too: otherwise a change from another device would wait for the next screen visit.
@Suite("Store save notifications")
struct StoreSaveNotificationTests {
    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0

        func increment() {
            lock.withLock { value += 1 }
        }

        var count: Int {
            lock.withLock { value }
        }
    }

    @Test
    func applyingAServerRowPostsDidSave() async throws {
        let sample = SampleData.standard
        let phone = try SwiftDataStore(modelContainer: ModelContainerFactory.make(store: .inMemory))
        let transaction = try #require(sample.transactions.first)
        try await phone.save(transaction)
        let event = try #require(try await phone.pendingEvents(limit: 100).first { $0.entity == "transaction" })

        let other = try SwiftDataStore(modelContainer: ModelContainerFactory.make(store: .inMemory))
        let saves = Counter()
        let observer = NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: nil, queue: nil) { _ in
            saves.increment()
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        try await other.applyRemote(entity: event.entity, row: event.payload)

        #expect(saves.count >= 1)
    }
}
