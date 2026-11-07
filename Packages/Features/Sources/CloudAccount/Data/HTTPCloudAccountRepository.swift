import CloudAccountDomain
import Foundation

/// The account through the API: Better Auth's endpoints for signing in and out, `GET /me` for who
/// is signed in.
public struct HTTPCloudAccountRepository: CloudAccountRepository {
    private let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    private struct UserDTO: Decodable {
        let id: String
        let name: String
        let email: String
        var domain: CloudAccountUser { CloudAccountUser(id: id, name: name, email: email) }
    }

    private struct MeDTO: Decodable {
        let user: UserDTO
        let capabilities: [String]?
        let early_access: [String]? // swiftlint:disable:this identifier_name
    }

    private struct ErrorDTO: Decodable {
        struct Detail: Decodable { let code: String? }
        let error: Detail?
        let code: String?
        // swiftlint:disable:next identifier_name
        let request_id: String?
    }

    private struct SignInBody: Encodable, Sendable {
        struct IDToken: Encodable, Sendable {
            let token: String
            let nonce: String
        }

        let provider = "apple"
        let idToken: IDToken
    }

    private struct Empty: Encodable, Sendable {}

    public func currentUser() async throws(CloudAccountError) -> CloudAccountUser? {
        guard client.hasSession else { return nil }
        let response = try await client.send("GET", "me")
        if response.status == 401 {
            client.clearSession()
            return nil
        }
        let me = try decode(MeDTO.self, response)
        return CloudAccountUser(
            id: me.user.id, name: me.user.name, email: me.user.email,
            capabilities: Set(me.capabilities ?? []), earlyAccess: Set(me.early_access ?? []),
        )
    }

    public func signIn(with credential: AppleCredential) async throws(CloudAccountError) -> CloudAccountUser {
        let body = SignInBody(idToken: .init(token: credential.idToken, nonce: credential.rawNonce))
        let response = try await client.send("POST", "api/auth/sign-in/social", json: body)
        if response.status == 403 {
            throw .notInvited
        }
        guard (200 ..< 300).contains(response.status) else { throw failure(response) }
        guard let user = try await currentUser() else { throw .signedOut }
        return user
    }

    public func signOut() async {
        _ = try? await client.send("POST", "api/auth/sign-out", json: Empty())
        client.clearSession()
    }

    public func signOutEverywhere() async throws(CloudAccountError) {
        let response = try await client.send("POST", "api/auth/revoke-sessions", json: Empty())
        if response.status == 401 {
            throw .signedOut
        }
        guard (200 ..< 300).contains(response.status) else { throw failure(response) }
    }

    public func disconnectAssistants() async throws(CloudAccountError) {
        let response = try await client.send("POST", "mcp/disconnect-all", json: Empty())
        if response.status == 401 {
            throw .signedOut
        }
        guard (200 ..< 300).contains(response.status) else { throw failure(response) }
    }

    public func deleteAccount() async throws(CloudAccountError) {
        let response = try await client.send("DELETE", "me")
        if response.status == 401 {
            client.clearSession()
            throw .signedOut
        }
        guard (200 ..< 300).contains(response.status) else { throw failure(response) }
        // The server already ended the session; forget the cookie.
        client.clearSession()
    }

    private func decode<T: Decodable>(_ type: T.Type, _ response: APIClient.Response) throws(CloudAccountError) -> T {
        guard (200 ..< 300).contains(response.status) else { throw failure(response) }
        do {
            return try JSONDecoder().decode(type, from: response.body)
        } catch {
            throw .server(code: "bad_response", requestID: nil)
        }
    }

    private func failure(_ response: APIClient.Response) -> CloudAccountError {
        let body = try? JSONDecoder().decode(ErrorDTO.self, from: response.body)
        return .server(code: body?.error?.code ?? body?.code ?? "http_\(response.status)", requestID: body?.request_id)
    }
}

extension Data {
    /// WebAuthn's encoding: base64url without padding.
    var base64URL: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(
            of: "=",
            with: "",
        )
    }

    init?(base64URL text: String) {
        var base64 = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        self.init(base64Encoded: base64)
    }
}

/// Better Auth's passkey endpoints, in the JSON shape SimpleWebAuthn uses on the web.
public struct HTTPPasskeySignIn: PasskeySignIn {
    private let client: APIClient
    private let account: HTTPCloudAccountRepository

    public init(client: APIClient) {
        self.client = client
        account = HTTPCloudAccountRepository(client: client)
    }

    private struct OptionsDTO: Decodable {
        let challenge: String
        let rpId: String
    }

    private struct Body: Encodable, Sendable {
        struct Response: Encodable, Sendable {
            let clientDataJSON: String
            let authenticatorData: String
            let signature: String
            let userHandle: String?
        }

        struct Credential: Encodable, Sendable {
            let id: String
            let rawId: String
            let type = "public-key"
            let authenticatorAttachment = "platform"
            let response: Response
            let clientExtensionResults: [String: String] = [:]
        }

        let response: Credential
    }

    public func options() async throws(CloudAccountError) -> PasskeyOptions {
        let response = try await client.send("GET", "api/auth/passkey/generate-authenticate-options")
        guard (200 ..< 300).contains(response.status),
              let dto = try? JSONDecoder().decode(OptionsDTO.self, from: response.body),
              let challenge = Data(base64URL: dto.challenge)
        else { throw .server(code: "passkey_options", requestID: nil) }
        return PasskeyOptions(challenge: challenge, relyingParty: dto.rpId)
    }

    public func signIn(with assertion: PasskeyAssertion) async throws(CloudAccountError) -> CloudAccountUser {
        let id = assertion.credentialID.base64URL
        let body = Body(response: .init(
            id: id,
            rawId: id,
            response: .init(
                clientDataJSON: assertion.clientDataJSON.base64URL,
                authenticatorData: assertion.authenticatorData.base64URL,
                signature: assertion.signature.base64URL,
                userHandle: assertion.userHandle?.base64URL,
            ),
        ))
        let response = try await client.send("POST", "api/auth/passkey/verify-authentication", json: body)
        guard (200 ..< 300).contains(response.status) else { throw .server(code: "passkey_rejected", requestID: nil) }
        guard let user = try await account.currentUser() else { throw .signedOut }
        return user
    }
}
