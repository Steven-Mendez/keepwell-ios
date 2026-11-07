import CloudAccountDomain
import Foundation

/// Talks to the Keepwell API. Sends the session cookie from `SessionStore` on every request and
/// keeps whatever session cookie the server sets; a URLSession with no cookie storage of its own,
/// so nothing about the session lives outside the Keychain.
public final class APIClient: Sendable {
    public struct Response: Sendable {
        public let status: Int
        public let body: Data
    }

    /// Better Auth's session cookies: `better-auth.session_token` locally, `__Secure-` in production.
    static let sessionCookieMarker = "better-auth.session_"

    private let baseURL: URL
    private let session: URLSession
    private let store: any SessionStore

    public init(baseURL: URL, store: any SessionStore, configuration: URLSessionConfiguration = .ephemeral) {
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        self.baseURL = baseURL
        self.store = store
        session = URLSession(configuration: configuration)
    }

    public var hasSession: Bool { store.load() != nil }

    public func clearSession() {
        store.clear()
    }

    public func send(
        _ method: String,
        _ path: String,
        json: (any Encodable & Sendable)? = nil,
    ) async throws(CloudAccountError) -> Response {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // Better Auth checks the origin of cookie-authenticated writes; the API trusts its own.
        request.setValue(baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")), forHTTPHeaderField: "Origin")
        if let cookie = store.load() {
            request.setValue(cookie, forHTTPHeaderField: "Cookie")
        }
        if let json {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONEncoder().encode(json)
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw .unreachable
        }
        guard let http = response as? HTTPURLResponse else { throw .unreachable }
        keepSessionCookie(from: http)
        return Response(status: http.statusCode, body: data)
    }

    private func keepSessionCookie(from response: HTTPURLResponse) {
        let headers = response.allHeaderFields.reduce(into: [String: String]()) { result, pair in
            if let key = pair.key as? String, let value = pair.value as? String {
                result[key] = value
            }
        }
        let cookies = HTTPCookie.cookies(withResponseHeaderFields: headers, for: baseURL)
            .filter { $0.name.contains(Self.sessionCookieMarker) }
        guard !cookies.isEmpty else { return }
        // A cookie set to expire (sign-out) clears the session.
        if cookies.allSatisfy({ $0.value.isEmpty || ($0.expiresDate.map { $0 < .now } ?? false) }) {
            store.clear()
            return
        }
        store.save(cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; "))
    }
}
