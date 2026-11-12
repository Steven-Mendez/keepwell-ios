import Foundation
import SwiftUI
import UIKit

/// Brand logos come from Brandfetch's Logo API, requested live: its terms forbid storing them or
/// serving them ourselves, so only `URLSession`'s normal HTTP cache keeps them. This is the one
/// third party the app calls; Brandfetch sees the device's IP address and the domain of each brand
/// shown, never a description, a rule's name or anything else typed.
public protocol BrandLogoProviding: Sendable {
    /// The brand's logo, or `nil` when it can't be shown (the row keeps its monogram).
    func logo(for domain: String, theme: BrandLogoTheme) async -> UIImage?
}

public enum BrandLogoTheme: String, Sendable {
    case light
    case dark

    public init(_ scheme: ColorScheme) {
        self = scheme == .dark ? .dark : .light
    }
}

/// The build's switch and Brandfetch's client id (public by design: it travels in every URL; not
/// the account's secret API key). Off, or without a client id, nothing is ever requested.
public struct BrandLogoConfiguration: Sendable, Equatable {
    public let isEnabled: Bool
    public let clientID: String?

    public init(isEnabled: Bool, clientID: String?) {
        self.isEnabled = isEnabled
        self.clientID = clientID.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
    }

    public var isActive: Bool {
        isEnabled && clientID != nil
    }
}

/// The session's memory of Brandfetch (nothing is stored): a domain that failed is not asked
/// again, and after a few failures of different domains in a row the logos stop until the app
/// relaunches. A failure for lack of network, or a request the row cancelled, isn't remembered.
public actor BrandfetchLogos: BrandLogoProviding {
    public typealias Fetch = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    public static let host = "cdn.brandfetch.io"
    public static let failureLimit = 3

    private let configuration: BrandLogoConfiguration
    private let fetch: Fetch
    private var failed: Set<String> = []
    private var loaded: Set<String> = []
    private var failuresInARow = 0
    private var inFlight: [String: Task<UIImage?, Never>] = [:]

    /// `fetch` is `URLSession.shared.data(for:)` in the app, so the system's HTTP cache applies.
    public init(configuration: BrandLogoConfiguration, fetch: @escaping Fetch) {
        self.configuration = configuration
        self.fetch = fetch
    }

    /// Square icon, 128 px (the 40 pt badge at 3×), and a 404 for an unknown brand instead of a
    /// transparent image that would read as success.
    public static func url(domain: String, theme: BrandLogoTheme, clientID: String) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = "/domain/\(domain)/w/128/h/128/theme/\(theme.rawValue)/fallback/404/type/icon"
        components.queryItems = [URLQueryItem(name: "c", value: clientID)]
        return components.url
    }

    public var isStopped: Bool {
        failuresInARow >= Self.failureLimit
    }

    public func logo(for domain: String, theme: BrandLogoTheme) async -> UIImage? {
        guard configuration.isActive, let clientID = configuration.clientID else { return nil }
        // A logo already shown stays, even after the session stops asking for new ones.
        if !loaded.contains(domain), isStopped || failed.contains(domain) {
            return nil
        }
        guard let url = Self.url(domain: domain, theme: theme, clientID: clientID) else { return nil }
        let key = url.absoluteString
        if let running = inFlight[key] {
            return await running.value
        }
        let task = Task { await self.request(url, domain: domain) }
        inFlight[key] = task
        let image = await task.value
        inFlight[key] = nil
        return image
    }

    private func request(_ url: URL, domain: String) async -> UIImage? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        do {
            let (data, response) = try await fetch(request)
            if let image = Self.logo(from: data, response: response) {
                failuresInARow = 0
                loaded.insert(domain)
                return image
            }
        } catch {
            if Self.isTransient(error) {
                return nil
            }
        }
        if failed.insert(domain).inserted {
            failuresInARow += 1
        }
        return nil
    }

    /// The logo only when Brandfetch itself answered 200 with an image. Its refusals don't fail:
    /// they redirect to its guidelines page, which `URLSession` follows to an HTML page on another
    /// host, so the final host and the type are checked as well as the status.
    static func logo(from data: Data, response: URLResponse) -> UIImage? {
        guard let http = response as? HTTPURLResponse,
              http.statusCode == 200,
              http.url?.host == host,
              http.mimeType?.hasPrefix("image/") == true,
              let image = UIImage(data: data),
              image.size.width > 0
        else { return nil }
        return image
    }

    /// No network, or the row went away: show the monogram now and ask again later.
    private static func isTransient(_ error: any Error) -> Bool {
        if error is CancellationError {
            return true
        }
        guard let error = error as? URLError else { return false }
        return [.cancelled, .notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff, .networkConnectionLost]
            .contains(error.code)
    }
}

extension EnvironmentValues {
    /// Brandfetch for the rows; `nil` (previews, snapshots, the switch off) shows only monograms.
    @Entry public var brandLogos: (any BrandLogoProviding)?
}
