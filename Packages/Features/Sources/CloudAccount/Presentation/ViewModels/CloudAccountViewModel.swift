import CloudAccountDomain
import CryptoKit
import Foundation
import Observation

@MainActor
@Observable
public final class CloudAccountViewModel {
    public enum State: Equatable {
        case loading
        case signedOut
        case signedIn(CloudAccountUser)
    }

    public private(set) var state = State.loading
    public private(set) var isWorking = false
    public private(set) var errorMessage: String?
    /// The raw nonce of the sign-in in progress; Apple only sees its SHA-256.
    private var pendingNonce: String?

    private let load: any LoadCloudAccountUseCase
    private let signIn: any SignInWithAppleUseCase
    private let signOutUseCase: any SignOutUseCase
    private let deleteUseCase: any DeleteCloudAccountUseCase

    public init(
        load: any LoadCloudAccountUseCase,
        signIn: any SignInWithAppleUseCase,
        signOut: any SignOutUseCase,
        delete: any DeleteCloudAccountUseCase,
    ) {
        self.load = load
        self.signIn = signIn
        signOutUseCase = signOut
        deleteUseCase = delete
    }

    public func refresh() async {
        do {
            state = try await load.execute().map(State.signedIn) ?? .signedOut
            errorMessage = nil
        } catch {
            // Offline at launch: say so, but don't pretend the person is signed out.
            if state == .loading {
                state = .signedOut
            }
            errorMessage = message(for: error)
        }
    }

    /// The nonce to put on Apple's request, hashed as Apple expects.
    public func prepareAppleRequest() -> String {
        let raw = (0 ..< 32).map { _ in String(format: "%02x", UInt8.random(in: .min ... .max)) }.joined()
        pendingNonce = raw
        return Self.sha256(raw)
    }

    public func completeAppleSignIn(idToken: String) async {
        guard let nonce = pendingNonce else { return }
        pendingNonce = nil
        await run { () async throws(CloudAccountError) in
            let user = try await self.signIn.execute(AppleCredential(idToken: idToken, rawNonce: nonce))
            self.state = .signedIn(user)
        }
    }

    /// Apple's sheet failed or was dismissed; a cancel isn't an error worth showing.
    public func appleSignInFailed(cancelled: Bool) {
        pendingNonce = nil
        if !cancelled {
            errorMessage = String(localized: "Couldn't sign in with Apple. Try again.", bundle: #bundle)
        }
    }

    public func signOut(everywhere: Bool) async {
        await run { () async throws(CloudAccountError) in
            try await self.signOutUseCase.execute(everywhere: everywhere)
            self.state = .signedOut
        }
    }

    public func deleteAccount() async {
        await run { () async throws(CloudAccountError) in
            try await self.deleteUseCase.execute()
            self.state = .signedOut
        }
    }

    private func run(_ work: @escaping () async throws(CloudAccountError) -> Void) async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await work()
            errorMessage = nil
        } catch {
            if error == .signedOut {
                state = .signedOut
            }
            errorMessage = message(for: error)
        }
    }

    private func message(for error: CloudAccountError) -> String {
        switch error {
        case .notInvited:
            String(localized: "Keepwell accounts are invite-only for now.", bundle: #bundle)
        case .signedOut:
            String(localized: "You were signed out. Sign in again to keep syncing.", bundle: #bundle)
        case .unreachable, .server:
            String(localized: "Couldn't reach Keepwell. Try again.", bundle: #bundle)
        }
    }

    static func sha256(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
