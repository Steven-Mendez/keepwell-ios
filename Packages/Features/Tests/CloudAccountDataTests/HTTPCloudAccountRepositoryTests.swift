import CloudAccountData
import CloudAccountDomain
import Foundation
import Testing

/// Answers requests from a script, and records them, instead of the network.
final class StubProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (Int, [String: String], Data))?
    nonisolated(unsafe) static var requests: [URLRequest] = []

    override static func canInit(with _: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        var recorded = request
        if let stream = request.httpBodyStream {
            stream.open()
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 {
                    break
                }
                data.append(buffer, count: count)
            }
            recorded.httpBody = data
        }
        Self.requests.append(recorded)
        let (status, headers, body) = Self.handler?(request) ?? (500, [:], Data())
        guard let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: headers)
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite("Account over HTTP", .serialized)
struct HTTPCloudAccountRepositoryTests {
    private let base = URL(string: "https://api.example.com")!

    private func repository(_ store: InMemorySessionStore) -> HTTPCloudAccountRepository {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        StubProtocol.requests = []
        return HTTPCloudAccountRepository(client: APIClient(baseURL: base, store: store, configuration: configuration))
    }

    private let me = Data(#"{"user":{"id":"u1","name":"Ana","email":"ana@example.com"}}"#.utf8)

    @Test
    func signInKeepsTheSessionCookieInTheStoreAndSendsItBack() async throws {
        let store = InMemorySessionStore()
        let repository = repository(store)
        StubProtocol.handler = { request in
            switch request.url?.path {
            case "/api/auth/sign-in/social":
                (200, ["Set-Cookie": "__Secure-better-auth.session_token=abc.def; Path=/; HttpOnly; Secure; SameSite=Lax"], Data("{}".utf8))
            case "/me":
                request.value(forHTTPHeaderField: "Cookie") == "__Secure-better-auth.session_token=abc.def" ? (200, [:], me) : (
                    401,
                    [:],
                    Data(),
                )
            default:
                (404, [:], Data())
            }
        }
        let user = try await repository.signIn(with: AppleCredential(idToken: "jwt", rawNonce: "raw"))
        #expect(user == CloudAccountUser(id: "u1", name: "Ana", email: "ana@example.com"))
        #expect(store.load() == "__Secure-better-auth.session_token=abc.def")

        let body = try #require(StubProtocol.requests.first?.httpBody)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["provider"] as? String == "apple")
        #expect((json["idToken"] as? [String: String]) == ["token": "jwt", "nonce": "raw"])
    }

    @Test
    func aRejectedAppleIDIsNotInvited() async {
        let store = InMemorySessionStore()
        let repository = repository(store)
        StubProtocol.handler = { _ in (403, [:], Data(#"{"code":"NOT_INVITED"}"#.utf8)) }
        await #expect(throws: CloudAccountError.notInvited) {
            try await repository.signIn(with: AppleCredential(idToken: "jwt", rawNonce: "raw"))
        }
        #expect(store.load() == nil)
    }

    @Test
    func aSessionTheServerNoLongerKnowsIsForgotten() async throws {
        let store = InMemorySessionStore(cookie: "better-auth.session_token=old")
        let repository = repository(store)
        StubProtocol.handler = { _ in (401, [:], Data()) }
        #expect(try await repository.currentUser() == nil)
        #expect(store.load() == nil)
    }

    @Test
    func withoutASessionNothingIsAsked() async throws {
        let repository = repository(InMemorySessionStore())
        StubProtocol.handler = { _ in (500, [:], Data()) }
        #expect(try await repository.currentUser() == nil)
        #expect(StubProtocol.requests.isEmpty)
    }

    @Test
    func signOutClearsTheSessionEvenOffline() async {
        let store = InMemorySessionStore(cookie: "better-auth.session_token=x")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        StubProtocol.handler = { _ in (500, [:], Data()) }
        await HTTPCloudAccountRepository(client: APIClient(baseURL: base, store: store, configuration: configuration)).signOut()
        #expect(store.load() == nil)
    }
}
