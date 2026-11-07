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
