import Foundation
import Testing
import UIKit
@testable import SharedPresentation

/// The cases keepwell-web runs too (`brand-cases.json`, copied verbatim). If one fails, a matching
/// rule changed on one platform only, and the same movement would show a logo on one and not the other.
@Suite("Brand matching")
struct BrandMatchingTests {
    private struct Cases: Decodable {
        struct Normalize: Decodable {
            let text: String
            let normalized: String
        }

        struct Match: Decodable {
            let text: String
            let brand: String?
        }

        let normalize: [Normalize]
        let brandFor: [Match]
    }

    private static func cases() throws -> Cases {
        let url = try #require(Bundle.module.url(forResource: "brand-cases", withExtension: "json", subdirectory: "Fixtures"))
        return try JSONDecoder().decode(Cases.self, from: Data(contentsOf: url))
    }

    @Test
    func tableShipsWithTheApp() {
        #expect(BrandCatalog.brands.count >= 60)
        #expect(BrandCatalog.brand(for: "Claro")?.domain == "claro.com.ni")
        #expect(BrandCatalog.brand(for: "Tigo")?.domain == "tigo.com.ni")
    }

    @Test
    func normalizesLikeTheWeb() throws {
        for item in try Self.cases().normalize {
            #expect(BrandCatalog.normalize(item.text) == item.normalized, "\(item.text)")
        }
    }

    @Test
    func matchesLikeTheWeb() throws {
        for item in try Self.cases().brandFor {
            #expect(BrandCatalog.brand(for: item.text)?.id == item.brand, "\(item.text)")
        }
    }

    @Test
    func monogramIsTheFirstLetterOrDigit() throws {
        let spotify = try #require(BrandCatalog.brand(for: "Spotify"))
        let onePassword = try #require(BrandCatalog.brand(for: "1Password"))
        #expect(spotify.monogram == "S")
        #expect(onePassword.monogram == "1")
    }
}

/// The chain a row follows: Brandfetch's logo when it answers with one, the monogram otherwise.
@Suite("Brandfetch logos")
struct BrandfetchLogosTests {
    private static let on = BrandLogoConfiguration(isEnabled: true, clientID: "client")

    /// Answers every request with `answer` and records what was asked.
    private final class Server: @unchecked Sendable {
        private let lock = NSLock()
        private var asked: [URLRequest] = []
        let answer: @Sendable (URLRequest) throws -> (Data, URLResponse)

        init(_ answer: @escaping @Sendable (URLRequest) throws -> (Data, URLResponse)) {
            self.answer = answer
        }

        var requests: [URLRequest] {
            lock.withLock { asked }
        }

        func logos(_ configuration: BrandLogoConfiguration = BrandfetchLogosTests.on) -> BrandfetchLogos {
            BrandfetchLogos(configuration: configuration) { request in
                self.lock.withLock { self.asked.append(request) }
                return try self.answer(request)
            }
        }
    }

    private static func response(_ url: URL?, status: Int, type: String) -> HTTPURLResponse {
        let url = url ?? URL(filePath: "/")
        return HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/2", headerFields: ["Content-Type": type])
            ?? HTTPURLResponse()
    }

    private static let png: Data = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).pngData { context in
        UIColor.green.setFill()
        context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
    }

    private static let answers = Server { request in (png, response(request.url, status: 200, type: "image/png")) }
    /// A refusal: a 302 to the guidelines, which `URLSession` follows to an HTML page elsewhere.
    private static let redirects = Server { _ in
        let page = URL(string: "https://docs.brandfetch.com/docs/logo-link/guidelines#2-hotlinking")
        return (Data("<html></html>".utf8), response(page, status: 200, type: "text/html"))
    }

    @Test
    func asksOnlyForTheTableBrandsDomain() async throws {
        let server = Server { request in (Self.png, Self.response(request.url, status: 200, type: "image/png")) }
        let brand = try #require(BrandCatalog.brand(for: "Spotify Premium familia Pérez"))
        _ = await server.logos().logo(for: brand.domain, theme: .dark)
        let url = try #require(server.requests.first?.url?.absoluteString)
        #expect(url == "https://cdn.brandfetch.io/domain/spotify.com/w/128/h/128/theme/dark/fallback/404/type/icon?c=client")
        #expect(BrandCatalog.brand(for: "Almuerzo con Pérez") == nil)
    }

    @Test
    func logoShowsWhenBrandfetchAnswers() async {
        let image = await Self.answers.logos().logo(for: "spotify.com", theme: .light)
        #expect(image != nil)
    }

    @Test
    func notFoundKeepsTheMonogramAndIsNotAskedAgain() async {
        let server = Server { request in (Data(), Self.response(request.url, status: 404, type: "application/json")) }
        let logos = server.logos()
        #expect(await logos.logo(for: "tigo.com.ni", theme: .light) == nil)
        #expect(await logos.logo(for: "tigo.com.ni", theme: .light) == nil)
        #expect(server.requests.count == 1)
    }

    @Test
    func redirectCountsAsAFailure() async {
        let logos = Self.redirects.logos()
        #expect(await logos.logo(for: "netflix.com", theme: .light) == nil)
        #expect(BrandfetchLogos.logo(from: Self.png, response: Self.response(
            URL(string: "https://docs.brandfetch.com/x"),
            status: 200,
            type: "image/png",
        )) == nil)
    }

    @Test
    func offlineKeepsTheMonogramAndAsksAgainLater() async {
        let server = Server { _ in throw URLError(.notConnectedToInternet) }
        let logos = server.logos()
        for domain in ["a.com", "b.com", "c.com", "a.com"] {
            #expect(await logos.logo(for: domain, theme: .light) == nil)
        }
        #expect(server.requests.count == 4)
        #expect(await logos.isStopped == false)
    }

    @Test
    func stopsAfterFailuresInARowKeepingShownLogos() async {
        let server = Server { request in
            request.url?.path.contains("spotify.com") == true
                ? (Self.png, Self.response(request.url, status: 200, type: "image/png"))
                : (Data(), Self.response(request.url, status: 404, type: "application/json"))
        }
        let logos = server.logos()
        #expect(await logos.logo(for: "spotify.com", theme: .light) != nil)
        for domain in ["a.com", "b.com"] {
            _ = await logos.logo(for: domain, theme: .light)
        }
        #expect(await logos.isStopped == false)
        _ = await logos.logo(for: "c.com", theme: .light)
        #expect(await logos.isStopped)
        let asked = server.requests.count
        #expect(await logos.logo(for: "netflix.com", theme: .light) == nil)
        #expect(server.requests.count == asked)
        #expect(await logos.logo(for: "spotify.com", theme: .light) != nil)
    }

    @Test
    func timeoutIsAFailure() async {
        let server = Server { _ in throw URLError(.timedOut) }
        let logos = server.logos()
        _ = await logos.logo(for: "a.com", theme: .light)
        _ = await logos.logo(for: "a.com", theme: .light)
        #expect(server.requests.count == 1)
    }

    @Test
    func asksForNothingWhenOff() async {
        let server = Server { request in (Self.png, Self.response(request.url, status: 200, type: "image/png")) }
        #expect(await server.logos(BrandLogoConfiguration(isEnabled: false, clientID: "client"))
            .logo(for: "spotify.com", theme: .light) == nil)
        #expect(await server.logos(BrandLogoConfiguration(isEnabled: true, clientID: " ")).logo(for: "spotify.com", theme: .light) == nil)
        #expect(await server.logos(BrandLogoConfiguration(isEnabled: true, clientID: nil)).logo(for: "spotify.com", theme: .light) == nil)
        #expect(server.requests.isEmpty)
    }
}
