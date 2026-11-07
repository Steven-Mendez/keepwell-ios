import Foundation

public protocol LoadCloudAccountUseCase: Sendable {
    func execute() async throws(CloudAccountError) -> CloudAccountUser?
}

public protocol SignInWithAppleUseCase: Sendable {
    func execute(_ credential: AppleCredential) async throws(CloudAccountError) -> CloudAccountUser
}

public protocol SignOutUseCase: Sendable {
    func execute(everywhere: Bool) async throws(CloudAccountError)
}

public struct DefaultLoadCloudAccountUseCase: LoadCloudAccountUseCase {
    private let repository: any CloudAccountRepository

    public init(repository: any CloudAccountRepository) {
        self.repository = repository
    }

    public func execute() async throws(CloudAccountError) -> CloudAccountUser? {
        do {
            return try await repository.currentUser()
        } catch .signedOut {
            // A session revoked elsewhere reads the same as no session here.
            return nil
        }
    }
}

public struct DefaultSignInWithAppleUseCase: SignInWithAppleUseCase {
    private let repository: any CloudAccountRepository

    public init(repository: any CloudAccountRepository) {
        self.repository = repository
    }

    public func execute(_ credential: AppleCredential) async throws(CloudAccountError) -> CloudAccountUser {
        try await repository.signIn(with: credential)
    }
}

public struct DefaultSignOutUseCase: SignOutUseCase {
    private let repository: any CloudAccountRepository

    public init(repository: any CloudAccountRepository) {
        self.repository = repository
    }

    /// Everywhere first, then locally: if the server call fails, this iPhone keeps its session so
    /// the person can retry, instead of losing the only way to revoke the others.
    public func execute(everywhere: Bool) async throws(CloudAccountError) {
        if everywhere {
            try await repository.signOutEverywhere()
        }
        await repository.signOut()
    }
}

public protocol DeleteCloudAccountUseCase: Sendable {
    func execute() async throws(CloudAccountError)
}

/// App Store guideline 5.1.1: the account can be deleted from inside the app.
public struct DefaultDeleteCloudAccountUseCase: DeleteCloudAccountUseCase {
    private let repository: any CloudAccountRepository

    public init(repository: any CloudAccountRepository) {
        self.repository = repository
    }

    public func execute() async throws(CloudAccountError) {
        try await repository.deleteAccount()
    }
}
