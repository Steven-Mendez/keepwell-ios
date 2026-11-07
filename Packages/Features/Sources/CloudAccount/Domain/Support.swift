import Foundation

/// A purchase StoreKit has verified on the device, with the JWS Apple signed. The server verifies
/// the JWS again; the app never decides on its own what a purchase grants.
public struct StorePurchase: Sendable, Equatable {
    public let transactionID: UInt64
    public let signedTransaction: String

    public init(transactionID: UInt64, signedTransaction: String) {
        self.transactionID = transactionID
        self.signedTransaction = signedTransaction
    }
}

/// The App Store side of the coffee (StoreKit 2 in Data).
public protocol StoreRepository: Sendable {
    /// The localized price, such as "$2.99"; `nil` when the product can't be loaded.
    func displayPrice() async -> String?
    /// `nil` when the person cancelled or the purchase waits for approval (Ask to Buy).
    func purchase() async throws(CloudAccountError) -> StorePurchase?
    /// Asks the App Store for this Apple ID's purchases (it may ask to sign in), then returns them.
    func restore() async throws(CloudAccountError) -> [StorePurchase]
    /// Purchases bought but not yet confirmed by Keepwell (the app quit, or the network failed).
    func unfinished() async -> [StorePurchase]
    /// Tells StoreKit the purchase is delivered. Only after the server granted it.
    func finish(_ purchase: StorePurchase) async
}

/// The server side: POST /entitlements/app-store.
public protocol EntitlementRepository: Sendable {
    /// Retrying with the same key answers the first result; the server grants once per purchase.
    func redeem(_ signedTransaction: String, idempotencyKey: UUID) async throws(CloudAccountError) -> CloudAccountUser
}

/// What the coffee did.
public enum SupportOutcome: Equatable, Sendable {
    case granted(CloudAccountUser)
    /// Cancelled, or waiting for a parent's approval: nothing changed.
    case notCompleted
}

public protocol BuySupportUseCase: Sendable {
    func execute() async throws(CloudAccountError) -> SupportOutcome
}

/// Buys the coffee and has Keepwell grant `supporter`. StoreKit's transaction is finished only once
/// the server confirmed; until then it stays unfinished and `RedeemPendingPurchasesUseCase` retries.
public struct DefaultBuySupportUseCase: BuySupportUseCase {
    private let store: any StoreRepository
    private let entitlements: any EntitlementRepository

    public init(store: any StoreRepository, entitlements: any EntitlementRepository) {
        self.store = store
        self.entitlements = entitlements
    }

    public func execute() async throws(CloudAccountError) -> SupportOutcome {
        guard let purchase = try await store.purchase() else { return .notCompleted }
        let user = try await redeem(purchase, entitlements: entitlements)
        await store.finish(purchase)
        return .granted(user)
    }
}

public protocol RestorePurchasesUseCase: Sendable {
    /// The account as it is after resending every purchase; `nil` when this Apple ID has none.
    func execute() async throws(CloudAccountError) -> CloudAccountUser?
}

/// Restore on a new install: `AppStore.sync()`, then each purchase is sent again. The server keys
/// grants by the original transaction, so a resend never grants twice.
public struct DefaultRestorePurchasesUseCase: RestorePurchasesUseCase {
    private let store: any StoreRepository
    private let entitlements: any EntitlementRepository

    public init(store: any StoreRepository, entitlements: any EntitlementRepository) {
        self.store = store
        self.entitlements = entitlements
    }

    public func execute() async throws(CloudAccountError) -> CloudAccountUser? {
        var user: CloudAccountUser?
        for purchase in try await store.restore() {
            user = try await redeem(purchase, entitlements: entitlements)
            await store.finish(purchase)
        }
        return user
    }
}

public protocol RedeemPendingPurchasesUseCase: Sendable {
    func execute() async -> CloudAccountUser?
}

/// At launch, finishes purchases that were paid but never confirmed. Quiet: failures wait for the
/// next launch, and the money is never lost because StoreKit keeps the transaction unfinished.
public struct DefaultRedeemPendingPurchasesUseCase: RedeemPendingPurchasesUseCase {
    private let store: any StoreRepository
    private let entitlements: any EntitlementRepository

    public init(store: any StoreRepository, entitlements: any EntitlementRepository) {
        self.store = store
        self.entitlements = entitlements
    }

    public func execute() async -> CloudAccountUser? {
        var user: CloudAccountUser?
        for purchase in await store.unfinished() {
            guard let granted = try? await redeem(purchase, entitlements: entitlements) else { continue }
            user = granted
            await store.finish(purchase)
        }
        return user
    }
}

/// One key per redemption, reused for the network retries within it.
private func redeem(
    _ purchase: StorePurchase,
    entitlements: any EntitlementRepository,
) async throws(CloudAccountError) -> CloudAccountUser {
    let key = UUID()
    var attempt = 0
    while true {
        do {
            return try await entitlements.redeem(purchase.signedTransaction, idempotencyKey: key)
        } catch .unreachable where attempt < 2 {
            attempt += 1
        }
    }
}
