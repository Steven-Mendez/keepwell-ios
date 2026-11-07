import Foundation

/// The person's Keepwell account on the server (Sign in with Apple), which syncs this iPhone with
/// the web. Not to be confused with the money accounts in `Accounts`. Local use never needs it.
public struct CloudAccountUser: Hashable, Sendable {
    public let id: String
    public let name: String
    public let email: String

    public init(id: String, name: String, email: String) {
        self.id = id
        self.name = name
        self.email = email
    }
}

public enum CloudAccountError: Error, Equatable, Sendable {
    /// Registration is closed and this Apple ID isn't on the list.
    case notInvited
    /// The session is missing, expired or was revoked from another device.
    case signedOut
    /// No connection, or the server didn't answer.
    case unreachable
    /// The server refused the request; `requestID` is what support can look up.
    case server(code: String, requestID: String?)
}

/// What Apple's native sheet hands back: an ID token for the bundle ID and the raw nonce whose
/// SHA-256 was sent to Apple, so the server can tie the token to this attempt.
public struct AppleCredential: Sendable, Equatable {
    public let idToken: String
    public let rawNonce: String

    public init(idToken: String, rawNonce: String) {
        self.idToken = idToken
        self.rawNonce = rawNonce
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
}
