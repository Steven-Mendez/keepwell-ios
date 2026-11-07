import Foundation

/// The person's Keepwell account on the server (Sign in with Apple), which syncs this iPhone with
/// the web. Not to be confused with the money accounts in `Accounts`. Local use never needs it.
public struct CloudAccountUser: Hashable, Sendable {
    public let id: String
    public let name: String
    public let email: String
    /// `cloud_sync` and `mcp`, as GET /me resolves them; the app never infers them itself.
    public let capabilities: Set<String>
    /// Capabilities that come only from early access ("Sync included during early access").
    public let earlyAccess: Set<String>
    /// `free`, `supporter`… The coffee turns `free` into `supporter`.
    public let plan: String

    public init(
        id: String,
        name: String,
        email: String,
        capabilities: Set<String> = [],
        earlyAccess: Set<String> = [],
        plan: String = "free",
    ) {
        self.plan = plan
        self.id = id
        self.name = name
        self.email = email
        self.capabilities = capabilities
        self.earlyAccess = earlyAccess
    }

    public var canSync: Bool {
        capabilities.contains("cloud_sync")
    }

    /// Whether the coffee would add something: sync or Claude missing, or only lent by early access.
    public var canBeSupported: Bool {
        plan == "free"
    }
}

public enum CloudAccountError: Error, Equatable, Sendable {
    /// Registration is closed and this Apple ID isn't on the list.
    case notInvited
    /// The invitation code is unknown, expired or already used.
    case invalidInvitation
    /// This purchase already gave a plan to another Keepwell account.
    case purchaseBelongsToAnotherAccount
    /// The App Store refused or failed the purchase.
    case storeFailed
    /// The session is missing, expired or was revoked from another device.
    case signedOut
    /// No connection, or the server didn't answer.
    case unreachable
    /// The account's plan doesn't include what was asked (`403 needs_plan`).
    case needsPlan
    /// The server refused the request; `requestID` is what support can look up.
    case server(code: String, requestID: String?)
}

/// What Apple's native sheet hands back: an ID token for the bundle ID and the raw nonce whose
/// SHA-256 was sent to Apple, so the server can tie the token to this attempt.
public struct AppleCredential: Sendable, Equatable {
    public let idToken: String
    public let rawNonce: String
    /// For a first sign-in while registration is by invitation; ignored for existing accounts.
    public let invitation: String?

    public init(idToken: String, rawNonce: String, invitation: String? = nil) {
        self.idToken = idToken
        self.rawNonce = rawNonce
        self.invitation = invitation
    }
}

public protocol CloudAccountRepository: Sendable {
    /// `nil` when there is no session on this iPhone.
    func currentUser() async throws(CloudAccountError) -> CloudAccountUser?
    func signIn(with credential: AppleCredential) async throws(CloudAccountError) -> CloudAccountUser
    /// Ends this iPhone's session. Clears it locally even when the server can't be reached.
    func signOut() async
    /// Ends every session of the account, on every device.
    func signOutEverywhere() async throws(CloudAccountError)
    /// Asks the server to delete the account. Every session ends at once and the server erases the
    /// data in the background; the local data on this iPhone stays.
    func deleteAccount() async throws(CloudAccountError)
    /// Cuts every assistant connected through MCP at once (their tokens stop working right away).
    func disconnectAssistants() async throws(CloudAccountError)
}

extension CloudAccountRepository {
    public func disconnectAssistants() async throws(CloudAccountError) {}
}

/// What the server sends to start a passkey sign-in.
public struct PasskeyOptions: Sendable, Equatable {
    public let challenge: Data
    public let relyingParty: String

    public init(challenge: Data, relyingParty: String) {
        self.challenge = challenge
        self.relyingParty = relyingParty
    }
}

/// The signed answer from the system passkey sheet, sent back for verification.
public struct PasskeyAssertion: Sendable, Equatable {
    public let credentialID: Data
    public let clientDataJSON: Data
    public let authenticatorData: Data
    public let signature: Data
    public let userHandle: Data?

    public init(credentialID: Data, clientDataJSON: Data, authenticatorData: Data, signature: Data, userHandle: Data?) {
        self.credentialID = credentialID
        self.clientDataJSON = clientDataJSON
        self.authenticatorData = authenticatorData
        self.signature = signature
        self.userHandle = userHandle
    }
}

/// Passkey sign-in (increment 22), separate from the account repository so builds without it stay simple.
public protocol PasskeySignIn: Sendable {
    func options() async throws(CloudAccountError) -> PasskeyOptions
    func signIn(with assertion: PasskeyAssertion) async throws(CloudAccountError) -> CloudAccountUser
}
