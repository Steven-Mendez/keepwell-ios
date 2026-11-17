import Domain
import Foundation

/// A brand Brandfetch's Brand Search found: a clean name and a valid domain.
public struct BrandSearchResult: Hashable, Sendable {
    public let name: String
    public let domain: String

    public init(name: String, domain: String) {
        self.name = name
        self.domain = domain
    }
}

/// Brandfetch's Brand Search API, called with the same public client id as the logos, only while
/// the person types in the "Business" or "Via" picker and nothing of their own matches. Brandfetch
/// sees the device's IP address and that text, never a description, a note or an amount. Nothing is
/// stored: `URLSession`'s HTTP cache is all there is. keepwell-web's `presentation/brand-search.ts`.
public protocol BrandSearching: Sendable {
    /// Empty when the logos are off, for a short query or when the request fails: the picker still
    /// offers creating the business by hand.
    func search(_ text: String) async -> [BrandSearchResult]
}

public enum BrandSearch {
    public static let host = "api.brandfetch.io"
    /// Shorter queries match half the internet; the picker waits for more.
    public static let minLength = 2
    /// How long typing must pause before the request goes out.
    public static let debounce = Duration.milliseconds(350)
    public static let limit = 5

    public static func url(query: String, clientID: String) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        // One path segment, as `encodeURIComponent` makes it: a "/" typed in the name is escaped too.
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove("/")
        let segment = query.trimmingCharacters(in: .whitespacesAndNewlines).addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        components.percentEncodedPath = "/v2/search/\(segment)"
        components.queryItems = [URLQueryItem(name: "c", value: clientID)]
        return components.url
    }

    /// The query as sent, or `nil` when it is too short to send.
    public static func query(_ text: String) -> String? {
        let query = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return query.count >= minLength ? query : nil
    }

    /// The results worth offering: a name and a valid domain each, trademark signs dropped
    /// ("Subway®"), one per domain, in Brandfetch's order, at most `limit`. Anything else is ignored.
    public static func parse(_ data: Data) -> [BrandSearchResult] {
        guard let entries = try? JSONSerialization.jsonObject(with: data) as? [Any] else { return [] }
        var seen = Set<String>()
        var results: [BrandSearchResult] = []
        for entry in entries {
            guard let object = entry as? [String: Any], let name = object["name"] as? String,
                  let rawDomain = object["domain"] as? String
            else { continue }
            let cleanName = name.filter { !"®™©℠".contains($0) }.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            guard !cleanName.isEmpty, let domain = Merchants.normalizedDomain(rawDomain), seen.insert(domain).inserted else {
                continue
            }
            results.append(BrandSearchResult(name: cleanName, domain: domain))
            if results.count == limit {
                break
            }
        }
        return results
    }
}

/// The app's `BrandSearching`, with the logos' configuration: off, or without a client id, it never
/// asks.
public struct BrandfetchSearch: BrandSearching {
    public typealias Fetch = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private let configuration: BrandLogoConfiguration
    private let fetch: Fetch

    /// `fetch` is `URLSession.shared.data(for:)` in the app.
    public init(configuration: BrandLogoConfiguration, fetch: @escaping Fetch) {
        self.configuration = configuration
        self.fetch = fetch
    }

    public func search(_ text: String) async -> [BrandSearchResult] {
        guard configuration.isActive, let clientID = configuration.clientID, let query = BrandSearch.query(text),
              let url = BrandSearch.url(query: query, clientID: clientID)
        else { return [] }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        guard let (data, response) = try? await fetch(request),
              let http = response as? HTTPURLResponse, http.statusCode == 200
        else { return [] }
        return BrandSearch.parse(data)
    }
}
