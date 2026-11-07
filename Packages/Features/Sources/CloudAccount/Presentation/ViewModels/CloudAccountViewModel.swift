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

    public private(set) var state = State.loading {
        didSet { followSync() }
    }

    public private(set) var isWorking = false
    public private(set) var errorMessage: String?
    /// The raw nonce of the sign-in in progress; Apple only sees its SHA-256.
    private var pendingNonce: String?

    private let load: any LoadCloudAccountUseCase
    private let signIn: any SignInWithAppleUseCase
    private let signOutUseCase: any SignOutUseCase
    private let deleteUseCase: any DeleteCloudAccountUseCase
    private let disconnectUseCase: (any DisconnectAssistantsUseCase)?
    /// Passkey sign-in; `nil` in builds without the web's associated domain.
    private let passkeys: (any PasskeySignIn)?
    public private(set) var assistantsDisconnected = false
    /// Runs sync while the account has `cloud_sync`; `nil` in previews and tests.
    public let sync: SyncCoordinator?

    public init(
        load: any LoadCloudAccountUseCase,
        signIn: any SignInWithAppleUseCase,
        signOut: any SignOutUseCase,
        delete: any DeleteCloudAccountUseCase,
        sync: SyncCoordinator? = nil,
        disconnectAssistants: (any DisconnectAssistantsUseCase)? = nil,
        passkeys: (any PasskeySignIn)? = nil,
    ) {
        self.passkeys = passkeys
        disconnectUseCase = disconnectAssistants
        self.sync = sync
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

    public var canUsePasskeys: Bool {
        passkeys != nil
    }

    /// Signs in with a passkey made on the web (same relying party through the associated domain).
    public func signInWithPasskey(using authorizer: PasskeyAuthorizer) async {
        guard let passkeys else { return }
        await run { () async throws(CloudAccountError) in
            let options = try await passkeys.options()
            let assertion: PasskeyAssertion
            do {
                assertion = try await authorizer.assert(options)
            } catch {
                // A dismissed sheet isn't worth an error.
                return
            }
            self.state = try await .signedIn(passkeys.signIn(with: assertion))
        }
    }

    /// "Disconnect everything" for assistants connected through MCP.
    public func disconnectAssistants() async {
        guard let disconnectUseCase else { return }
        await run { () async throws(CloudAccountError) in
            try await disconnectUseCase.execute()
            self.assistantsDisconnected = true
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
        case .needsPlan:
            String(localized: "Sync isn't included in your plan. Everything keeps working on this iPhone.", bundle: #bundle)
        case .unreachable, .server:
            String(localized: "Couldn't reach Keepwell. Try again.", bundle: #bundle)
        }
    }

    static func sha256(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Starts sync when an account with `cloud_sync` is signed in, stops it otherwise.
    private func followSync() {
        guard let sync else { return }
        if case let .signedIn(user) = state, user.canSync {
            sync.start()
            sync.resume()
        } else {
            sync.stop()
        }
    }
}
