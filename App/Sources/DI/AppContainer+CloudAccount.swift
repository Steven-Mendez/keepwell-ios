import CloudAccountData
import CloudAccountDomain
import CloudAccountPresentation
import Foundation

// MARK: - Keepwell account (API)

extension AppContainer {
    /// One client per app: it owns the session cookie in the Keychain. `nil` without an API URL.
    var apiClient: APIClient? {
        guard let url = AppEnvironment.current.apiBaseURL else { return nil }
        let service = (Bundle.main.bundleIdentifier ?? "Keepwell") + ".api-session"
        return APIClient(baseURL: url, store: KeychainSessionStore(service: service))
    }

    func makeCloudAccountViewModel() -> CloudAccountViewModel? {
        guard let client = apiClient else { return nil }
        let repository = HTTPCloudAccountRepository(client: client)
        return CloudAccountViewModel(
            load: DefaultLoadCloudAccountUseCase(repository: repository),
            signIn: DefaultSignInWithAppleUseCase(repository: repository),
            signOut: DefaultSignOutUseCase(repository: repository),
        )
    }
}
