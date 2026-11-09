import CloudAccountData
import CloudAccountDomain
import CloudAccountPresentation
import Foundation
import Persistence

// MARK: - Keepwell account and sync (API)

extension AppContainer {
    private var keychainService: String {
        (Bundle.main.bundleIdentifier ?? "Keepwell") + ".api-session"
    }

    /// One client per app: it owns the session cookie in the Keychain. `nil` without an API URL.
    var apiClient: APIClient? {
        guard let url = AppEnvironment.current.apiBaseURL else { return nil }
        return APIClient(baseURL: url, store: KeychainSessionStore(service: keychainService))
    }

    func makeCloudAccountViewModel() -> CloudAccountViewModel? {
        guard let client = apiClient else { return nil }
        let repository = HTTPCloudAccountRepository(client: client)
        let engine = SyncEngine(
            client: client,
            store: store,
            clientID: SyncClientID.load(from: KeychainSessionStore(service: keychainService, account: "sync-client-id")),
        )
        let store = store
        let coordinator = SyncCoordinator(
            run: { () async throws(CloudAccountError) in try await engine.syncOnce() },
            status: { await (engine.lastSync, store.pendingCount()) },
        )
        // A local change reaches the server a couple of seconds later.
        NotificationCenter.default.addObserver(forName: .keepwellOutboxChanged, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { coordinator.changed() }
        }
        return CloudAccountViewModel(
            load: DefaultLoadCloudAccountUseCase(repository: repository),
            signIn: DefaultSignInWithAppleUseCase(repository: repository),
            signOut: DefaultSignOutUseCase(repository: repository),
            delete: DefaultDeleteCloudAccountUseCase(repository: repository),
            sync: coordinator,
            disconnectAssistants: DefaultDisconnectAssistantsUseCase(repository: repository),
            passkeys: HTTPPasskeySignIn(client: client),
            support: makeSupportActions(repository: repository),
        )
    }

    /// The coffee: StoreKit for the purchase, the API to verify it and grant the plan.
    private func makeSupportActions(repository: HTTPCloudAccountRepository) -> SupportActions {
        let store = StoreKitStoreRepository()
        return SupportActions(
            buy: DefaultBuySupportUseCase(store: store, entitlements: repository),
            restore: DefaultRestorePurchasesUseCase(store: store, entitlements: repository),
            redeemPending: DefaultRedeemPendingPurchasesUseCase(store: store, entitlements: repository),
            price: { await store.displayPrice() },
        )
    }
}
