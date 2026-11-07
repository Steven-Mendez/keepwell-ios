import CloudAccountData
import CloudAccountDomain
import Foundation
import Testing

@Suite("Passkey sign-in over HTTP", .serialized)
struct PasskeySignInTests {
    private let base = URL(string: "https://api.example.com") ?? URL(fileURLWithPath: "/")

    @Test
    func readsTheChallengeAndSendsTheAssertionAsWebAuthnJSON() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        StubProtocol.requests = []
        let store = InMemorySessionStore()
        let passkeys = HTTPPasskeySignIn(client: APIClient(baseURL: base, store: store, configuration: configuration))
        StubProtocol.handler = { request in
            switch request.url?.path {
            case "/api/auth/passkey/generate-authenticate-options":
                (200, [:], Data(#"{"challenge":"AQID_-8","rpId":"app.example.com"}"#.utf8))
            case "/api/auth/passkey/verify-authentication":
                (200, ["Set-Cookie": "better-auth.session_token=s; Path=/"], Data("{}".utf8))
            case "/me":
                (
                    200,
                    [:],
                    Data(#"{"user":{"id":"u1","name":"Ana","email":"a@example.com"},"capabilities":["cloud_sync"],"early_access":[]}"#
                        .utf8),
                )
            default:
                (404, [:], Data())
            }
        }
        let options = try await passkeys.options()
        #expect(options.relyingParty == "app.example.com")
        #expect(options.challenge == Data([1, 2, 3, 255, 239]))

        let assertion = PasskeyAssertion(
            credentialID: Data([250, 251]),
            clientDataJSON: Data("{}".utf8),
            authenticatorData: Data([1]),
            signature: Data([2]),
            userHandle: nil,
        )
        let user = try await passkeys.signIn(with: assertion)
        #expect(user.canSync)
        let body = try #require(StubProtocol.requests.first { $0.url?.path == "/api/auth/passkey/verify-authentication" }?.httpBody)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let response = try #require(json["response"] as? [String: Any])
        #expect(response["id"] as? String == "-vs")
        #expect(response["type"] as? String == "public-key")
        #expect((response["response"] as? [String: Any])?["clientDataJSON"] as? String == "e30")
    }
}
