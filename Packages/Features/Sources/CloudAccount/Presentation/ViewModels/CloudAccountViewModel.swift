import CloudAccountDomain
import CryptoKit
import Foundation
import Observation

/// The coffee (increments 23 and 25): buy, restore, and finish purchases left halfway.
public struct SupportActions: Sendable {
    let buy: any BuySupportUseCase
    let restore: any RestorePurchasesUseCase
    let redeemPending: any RedeemPendingPurchasesUseCase
    let price: @Sendable () async -> String?

    public init(
        buy: any BuySupportUseCase,
        restore: any RestorePurchasesUseCase,
        redeemPending: any RedeemPendingPurchasesUseCase,
        price: @escaping @Sendable () async -> String?,
    ) {
        self.buy = buy
        self.restore = restore
        self.redeemPending = redeemPending
        self.price = price
    }
}

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
    /// The given name Apple shares on the first authorization only, kept for onboarding's name step.
    private var appleGivenName: String?

    private let load: any LoadCloudAccountUseCase
    private let signIn: any SignInWithAppleUseCase
    private let signOutUseCase: any SignOutUseCase
    private let deleteUseCase: any DeleteCloudAccountUseCase
    /// Takes this iPhone off the server's push list while the session still works; `nil` in
    /// previews and builds without push.
    private let unregisterPushDevice: (any UnregisterPushDeviceUseCase)?
    private let disconnectUseCase: (any DisconnectAssistantsUseCase)?
    private let listAssistantsUseCase: (any ListConnectedAssistantsUseCase)?
    private let disconnectOneUseCase: (any DisconnectAssistantUseCase)?
    /// The web's "How to connect Claude" page; `nil` without an API.
    public let connectGuideURL: URL?
    /// `nil` until the list loads (or when it can't be reached).
    public private(set) var assistants: [ConnectedAssistant]?
    /// Passkey sign-in; `nil` in builds without the web's associated domain.
    private let passkeys: (any PasskeySignIn)?
    public private(set) var assistantsDisconnected = false
    /// Invitation code for a first sign-in; existing accounts don't need one.
    public var invitation = ""
    /// The last sign-in was refused for lack of a valid invitation, so the code field should show.
    public private(set) var needsInvitation = false
    /// The coffee; `nil` in builds without in-app purchase.
    private let support: SupportActions?
    public private(set) var coffeePrice: String?
    /// A confirmation after buying or restoring ("Thank you…", "Nothing to restore").
    public private(set) var supportMessage: String?
    /// Runs sync while the account has `cloud_sync`; `nil` in previews and tests.
    public let sync: SyncCoordinator?

    public init(
        load: any LoadCloudAccountUseCase,
        signIn: any SignInWithAppleUseCase,
        signOut: any SignOutUseCase,
        delete: any DeleteCloudAccountUseCase,
        sync: SyncCoordinator? = nil,
        disconnectAssistants: (any DisconnectAssistantsUseCase)? = nil,
        listAssistants: (any ListConnectedAssistantsUseCase)? = nil,
        disconnectAssistant: (any DisconnectAssistantUseCase)? = nil,
        connectGuideURL: URL? = nil,
        passkeys: (any PasskeySignIn)? = nil,
        support: SupportActions? = nil,
        unregisterPushDevice: (any UnregisterPushDeviceUseCase)? = nil,
    ) {
        self.unregisterPushDevice = unregisterPushDevice
        self.support = support
        self.passkeys = passkeys
        disconnectUseCase = disconnectAssistants
        listAssistantsUseCase = listAssistants
        disconnectOneUseCase = disconnectAssistant
        self.connectGuideURL = connectGuideURL
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
            if case .signedIn = state, let support {
                // A purchase paid but never confirmed (the app quit, no network) is finished now.
                if let user = await support.redeemPending.execute() {
                    state = .signedIn(user)
                }
                coffeePrice = await support.price()
            }
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

    /// `givenName` is what Apple shared, if anything (only on the first authorization of this app).
    public func completeAppleSignIn(idToken: String, givenName: String? = nil) async {
        guard let nonce = pendingNonce else { return }
        pendingNonce = nil
        let trimmed = givenName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty {
            appleGivenName = trimmed
        }
        await run { () async throws(CloudAccountError) in
            let invitation = self.invitation.trimmingCharacters(in: .whitespacesAndNewlines)
            let credential = AppleCredential(idToken: idToken, rawNonce: nonce, invitation: invitation.isEmpty ? nil : invitation)
            let user = try await self.signIn.execute(credential)
            self.invitation = ""
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
            // Best effort and first: once signed out there is no session to ask with.
            try? await self.unregisterPushDevice?.execute()
            try await self.signOutUseCase.execute(everywhere: everywhere)
            self.state = .signedOut
        }
    }

    public var isSignedIn: Bool {
        if case .signedIn = state {
            true
        } else {
            false
        }
    }

    /// Before "Delete all my data": signing out first means nothing syncs between the erase and
    /// the sign-out, and a failed sign-out erases nothing. `true` when nobody is signed in any more.
    public func signOutBeforeErasing() async -> Bool {
        guard isSignedIn else { return true }
        await signOut(everywhere: false)
        return !isSignedIn
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

    public var canBuySupport: Bool {
        support != nil
    }

    /// Buys the coffee. Cancelling, or waiting for Ask to Buy, changes nothing and shows nothing.
    public func buyCoffee() async {
        guard let support else { return }
        // No price means the App Store didn't hand over the product (offline, or not on sale yet):
        // buying would only end in a vague store error, so ask again and say what's wrong.
        if coffeePrice == nil {
            coffeePrice = await support.price()
            guard coffeePrice != nil else {
                errorMessage = String(
                    localized: "The coffee isn't available in the App Store right now. Check your connection and try again later.",
                    bundle: #bundle,
                )
                return
            }
        }
        await run { () async throws(CloudAccountError) in
            if case let .granted(user) = try await support.buy.execute() {
                self.state = .signedIn(user)
                self.supportMessage = String(localized: "Thank you for the coffee. Sync and Claude are on.", bundle: #bundle)
            }
        }
    }

    /// On a new install or a new account: asks the App Store for past purchases and sends them again.
    public func restorePurchases() async {
        guard let support else { return }
        await run { () async throws(CloudAccountError) in
            if let user = try await support.restore.execute() {
                self.state = .signedIn(user)
                self.supportMessage = String(localized: "Purchase restored.", bundle: #bundle)
            } else {
                self.supportMessage = String(localized: "No purchases to restore for this Apple ID.", bundle: #bundle)
            }
        }
    }

    /// The assistants connected through MCP, for the list in Settings.
    public func loadAssistants() async {
        guard let listAssistantsUseCase else { return }
        assistants = await (try? listAssistantsUseCase.execute()) ?? []
    }

    /// Cuts one assistant off and reloads the list.
    public func disconnectAssistant(_ id: String) async {
        guard let disconnectOneUseCase else { return }
        await run { () async throws(CloudAccountError) in
            try await disconnectOneUseCase.execute(id: id)
        }
        await loadAssistants()
    }

    /// "Disconnect everything" for assistants connected through MCP.
    public func disconnectAssistants() async {
        guard let disconnectUseCase else { return }
        await run { () async throws(CloudAccountError) in
            try await disconnectUseCase.execute()
            self.assistantsDisconnected = true
        }
        await loadAssistants()
    }

    public func deleteAccount() async {
        await run { () async throws(CloudAccountError) in
            try? await self.unregisterPushDevice?.execute()
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
            needsInvitation = false
        } catch {
            if error == .signedOut {
                state = .signedOut
            }
            needsInvitation = error == .notInvited || error == .invalidInvitation
            errorMessage = message(for: error)
        }
    }

    private func message(for error: CloudAccountError) -> String {
        switch error {
        case .notInvited:
            String(localized: "Keepwell accounts are invite-only for now. Enter an invitation code first.", bundle: #bundle)
        case .invalidInvitation:
            String(localized: "That invitation is not valid. It may have expired or been used.", bundle: #bundle)
        case .purchaseBelongsToAnotherAccount:
            String(localized: "This purchase is already linked to another Keepwell account.", bundle: #bundle)
        case .storeFailed:
            String(localized: "The App Store couldn't complete the purchase. Try again.", bundle: #bundle)
        case .signedOut:
            String(localized: "You were signed out. Sign in again to keep syncing.", bundle: #bundle)
        case .needsPlan:
            String(localized: "Sync isn't included in your plan. Everything keeps working on this iPhone.", bundle: #bundle)
        case .unreachable, .server:
            String(localized: "Couldn't reach Keepwell. Try again.", bundle: #bundle)
        }
    }

    /// What onboarding's name step can start from: the name Apple shared at sign-in, otherwise the
    /// first word of the account's name. Never the email, which isn't how anyone is greeted.
    public func suggestedName(for user: CloudAccountUser) -> String? {
        if let appleGivenName {
            return appleGivenName
        }
        let name = user.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !name.contains("@"), name != user.email else { return nil }
        return name.split(separator: " ").first.map(String.init)
    }

    static func sha256(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Starts sync when an account with `cloud_sync` is signed in, stops it otherwise.
    private func followSync() {
        guard let sync else { return }
        if case let .signedIn(user) = state, user.canSync {
            sync.accountID = user.id
            sync.start()
            sync.resume()
        } else {
            sync.stop()
        }
    }
}
