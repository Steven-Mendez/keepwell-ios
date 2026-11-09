import CloudAccountDomain
import Foundation
import Testing

private actor FakeStore: StoreRepository {
    var next: StorePurchase?
    var owned: [StorePurchase] = []
    var pending: [StorePurchase] = []
    private(set) var finished: [UInt64] = []

    init(next: StorePurchase? = nil, owned: [StorePurchase] = [], pending: [StorePurchase] = []) {
        self.next = next
        self.owned = owned
        self.pending = pending
    }

    func displayPrice() async -> String? {
        "$2.99"
    }

    func purchase() async throws(CloudAccountError) -> StorePurchase? {
        next
    }

    func restore() async throws(CloudAccountError) -> [StorePurchase] {
        owned
    }

    func unfinished() async -> [StorePurchase] {
        pending
    }

    func finish(_ purchase: StorePurchase) async {
        finished.append(purchase.transactionID)
    }
}

private actor FakeEntitlements: EntitlementRepository {
    var failures: [CloudAccountError]
    private(set) var keys: [UUID] = []

    init(failures: [CloudAccountError] = []) {
        self.failures = failures
    }

    func redeem(_: String, idempotencyKey: UUID) async throws(CloudAccountError) -> CloudAccountUser {
        keys.append(idempotencyKey)
        if !failures.isEmpty {
            throw failures.removeFirst()
        }
        return CloudAccountUser(id: "u1", name: "Ana", email: "a@x", capabilities: ["cloud_sync", "mcp"], plan: "supporter")
    }
}

@Suite("The coffee")
struct SupportUseCasesTests {
    private let coffee = StorePurchase(transactionID: 7, signedTransaction: "jws")

    @Test
    func aPurchaseIsFinishedOnlyAfterTheServerGrantedIt() async throws {
        let store = FakeStore(next: coffee)
        let outcome = try await DefaultBuySupportUseCase(store: store, entitlements: FakeEntitlements()).execute()
        guard case let .granted(user) = outcome else { Issue.record("not granted")
            return
        }
        #expect(user.plan == "supporter")
        #expect(await store.finished == [7])
    }

    @Test
    func aServerRefusalLeavesTheTransactionUnfinished() async {
        let store = FakeStore(next: coffee)
        await #expect(throws: CloudAccountError.purchaseBelongsToAnotherAccount) {
            try await DefaultBuySupportUseCase(store: store, entitlements: FakeEntitlements(failures: [.purchaseBelongsToAnotherAccount]))
                .execute()
        }
        #expect(await store.finished.isEmpty)
    }

    @Test
    func networkRetriesReuseOneIdempotencyKey() async throws {
        let entitlements = FakeEntitlements(failures: [.unreachable, .unreachable])
        _ = try await DefaultBuySupportUseCase(store: FakeStore(next: coffee), entitlements: entitlements).execute()
        let keys = await entitlements.keys
        #expect(keys.count == 3)
        #expect(Set(keys).count == 1)
    }

    @Test
    func cancellingChangesNothing() async throws {
        let entitlements = FakeEntitlements()
        #expect(try await DefaultBuySupportUseCase(store: FakeStore(), entitlements: entitlements).execute() == .notCompleted)
        #expect(await entitlements.keys.isEmpty)
    }

    @Test
    func restoreResendsEveryPurchaseAndSaysWhenThereIsNone() async throws {
        let store = FakeStore(owned: [coffee])
        #expect(try await DefaultRestorePurchasesUseCase(store: store, entitlements: FakeEntitlements()).execute()?.plan == "supporter")
        #expect(try await DefaultRestorePurchasesUseCase(store: FakeStore(), entitlements: FakeEntitlements()).execute() == nil)
    }

    @Test
    func aHalfDonePurchaseIsFinishedQuietlyOrLeftForNextTime() async {
        let store = FakeStore(pending: [coffee])
        #expect(await DefaultRedeemPendingPurchasesUseCase(
            store: store,
            entitlements: FakeEntitlements(failures: [.server(code: "x", requestID: nil)]),
        ).execute() == nil)
        #expect(await store.finished.isEmpty)
        #expect(await DefaultRedeemPendingPurchasesUseCase(store: store, entitlements: FakeEntitlements()).execute()?.plan == "supporter")
        #expect(await store.finished == [7])
    }
}
