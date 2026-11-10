import CloudAccountData
import CloudAccountDomain
import CloudAccountPresentation
import Foundation
import OnboardingDomain
import Persistence

// MARK: - Keepwell account and sync (API)

extension AppContainer {
    private var keychainService: String {
        (Bundle.main.bundleIdentifier ?? "Keepwell") + ".api-session"
    }

    /// It owns the session cookie in the Keychain. `nil` without an API URL.
    func makeAPIClient() -> APIClient? {
        guard let url = AppEnvironment.current.apiBaseURL else { return nil }
        return APIClient(baseURL: url, store: KeychainSessionStore(service: keychainService))
    }

    func makeSyncEngine() -> SyncEngine? {
        guard let client = apiClient else { return nil }
        return SyncEngine(
            client: client,
            store: store,
            clientID: SyncClientID.load(from: KeychainSessionStore(service: keychainService, account: "sync-client-id")),
        )
    }

    func makeCloudAccountViewModel() -> CloudAccountViewModel? {
        guard let client = apiClient, let engine = syncEngine else { return nil }
        let repository = HTTPCloudAccountRepository(client: client)
        let store = store
        let coordinator = SyncCoordinator(
            run: { account throws(CloudAccountError) in try await engine.syncOnce(account: account) },
            resolve: { choice, account throws(CloudAccountError) in try await engine.resolve(choice, account: account) },
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

    /// Onboarding's wait for an account's data after signing in; `nil` without an API, which also
    /// leaves the account step out of onboarding.
    func makeRestoreFromAccount() -> (any RestoreFromAccountUseCase)? {
        guard let sync = cloudAccount?.sync else { return nil }
        let store = store
        return DefaultRestoreFromAccountUseCase(
            settings: store,
            hasUserData: {
                let counts = await (try? store.localRowCounts()) ?? [:]
                return SyncDataSummary(counts: counts).hasUserData
            },
            completedSyncRounds: { await sync.completedRounds },
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
