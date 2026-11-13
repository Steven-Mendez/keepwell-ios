import Domain
import DomainSamples
import Foundation
import Testing
@testable import SharedPresentation

/// Logos, the "Business"/"Via" options and Brandfetch's brand search, as keepwell-web's
/// `presentation/merchants.ts` and `presentation/brand-search.ts`.
@Suite("Merchant presentation")
struct MerchantPresentationTests {
    private let subway = Merchant(name: "Subway Galerías", domain: "subway.com.ni", brandID: "subway")
    private let byBrand = Merchant(name: "Mi Netflix", brandID: "netflix")
    private let corner = Merchant(name: "Pulpería La Esquina")
    private let uberEats = Merchant(name: "Uber Eats", domain: "ubereats.com", brandID: "uber-eats", isPlatform: true)

    // MARK: Logos

    /// The merchant's own domain, then its brand's, then the brand the description names.
    @Test
    func aLogoComesFromTheMerchantsDomainThenItsBrandThenTheDescription() {
        #expect(MerchantLogos.logo(of: subway) == LogoSubject(name: "Subway Galerías", domain: "subway.com.ni"))
        #expect(MerchantLogos.logo(of: byBrand) == LogoSubject(name: "Mi Netflix", domain: "netflix.com"))
        #expect(MerchantLogos.logo(of: corner) == nil)
        #expect(MerchantLogos.logo(description: "Spotify", merchant: subway)?.domain == "subway.com.ni")
        #expect(MerchantLogos.logo(description: "Spotify", merchant: corner)?.domain == "spotify.com")
        #expect(MerchantLogos.logo(description: "Spotify", merchant: nil)?.domain == "spotify.com")
        #expect(MerchantLogos.logo(description: "Pan dulce", merchant: corner) == nil)
        #expect(LogoSubject(name: "élan", domain: "x.com").monogram == "É")
    }

    @Test
    func theRowReadsTheBusinessAndPlatformAndSearchFindsThem() {
        let sample = SampleData.standard
        let display = TransactionDisplay(
            accounts: sample.accounts, cards: sample.cards, categories: sample.categories, merchants: [subway, uberEats],
        )
        let base = sample.transactions.first { $0.kind == .expense } ?? sample.transactions[0]
        let both = base.with(merchantID: subway.id, viaMerchantID: uberEats.id)
        #expect(display.merchantLine(of: both) == "Subway Galerías · via Uber Eats")
        #expect(display.merchantLine(of: base.with(merchantID: nil, viaMerchantID: uberEats.id)) == "via Uber Eats")
        #expect(display.merchantLine(of: base) == nil)
        #expect(display.subtitle(of: both).hasPrefix("Subway Galerías · via Uber Eats · "))
        #expect(display.searchableText(of: both).contains("galerias"))
        #expect(display.logo(of: both)?.domain == "subway.com.ni")
        // A merchant that no longer exists names nothing.
        #expect(display.merchantLine(of: base.with(merchantID: UUID(), viaMerchantID: nil)) == nil)
    }

    // MARK: Options

    @Test
    func optionsListYourMerchantsThenTheTablesBrandsThenTheWebThenAddingIt() {
        let remote = [
            BrandSearchResult(name: "Subway", domain: "subway.com.ni"),
            BrandSearchResult(name: "Submarino", domain: "submarino.com"),
        ]
        let options = MerchantOption.options(query: "sub", merchants: [subway, corner], remote: remote)
        // "Subway" of the table is yours already; "Substack" isn't.
        #expect(options.map(\.group) == [.mine, .brands, .web, .new])
        #expect(options.first?.choice == .merchant(subway.id))
        #expect(options[1].label == "Substack")
        // The domain already offered by your merchant isn't offered again from the web.
        #expect(options[2].label == "Submarino")
        #expect(options.last?.label == "sub")

        let brands = MerchantOption.options(query: "netf", merchants: [])
        #expect(brands.first?.group == .brands)
        #expect(brands.first?.choice == .new(MerchantDraft(name: "Netflix", domain: "netflix.com", brandID: "netflix")))
        // A brand you already have as a merchant isn't suggested again.
        #expect(!MerchantOption.options(query: "netf", merchants: [byBrand]).contains { $0.group == .brands })
        // A name you already have isn't offered to add.
        #expect(!MerchantOption.options(query: "pulpería la esquina", merchants: [corner]).contains { $0.group == .new })
    }

    @Test
    func viaOffersPlatformsFirstNeverTheBusinessAndCreatesPlatforms() {
        let options = MerchantOption.options(query: "", merchants: [subway, corner, uberEats], role: .via, excluding: subway.id)
        #expect(options.map(\.label) == ["Uber Eats", "Pulpería La Esquina"])
        let typed = MerchantOption.options(query: "Rappi", merchants: [], role: .via)
        #expect(typed.last?.choice == .new(MerchantDraft(name: "Rappi", isPlatform: true)))
    }

    @Test
    func theWebIsAskedOnlyForALongQueryNothingLocalMatches() {
        #expect(!MerchantOption.needsBrandSearch("s", local: []))
        #expect(MerchantOption.needsBrandSearch("zz", local: MerchantOption.options(query: "zz", merchants: [])))
        #expect(!MerchantOption.needsBrandSearch("sub", local: MerchantOption.options(query: "sub", merchants: [subway])))
        #expect(!MerchantOption.needsBrandSearch("netf", local: MerchantOption.options(query: "netf", merchants: [])))
    }

    @Test
    func theDescriptionSuggestsYourMerchantOrTheBrand() {
        #expect(MerchantLogos.suggestedMerchant(for: "Netflix monthly", merchants: [byBrand]) == .merchant(byBrand.id))
        #expect(MerchantLogos.suggestedMerchant(for: "Netflix monthly", merchants: [])
            == .new(MerchantDraft(name: "Netflix", domain: "netflix.com", brandID: "netflix")))
        #expect(MerchantLogos.suggestedMerchant(for: "Pan dulce", merchants: []) == nil)
    }

    // MARK: Brand search

    @Test
    func theSearchURLIsOneEscapedSegmentWithTheClientID() {
        let url = BrandSearch.url(query: "Pollo / Campero", clientID: "abc")
        #expect(url?.absoluteString == "https://api.brandfetch.io/v2/search/Pollo%20%2F%20Campero?c=abc")
        #expect(BrandSearch.query(" a ") == nil)
        #expect(BrandSearch.query("  Uber   Eats ") == "Uber Eats")
    }

    @Test
    func resultsAreCleanedDedupedAndCut() {
        let body = """
        [{"name":"Subway®","domain":"Subway.com"},{"name":"Subway","domain":"subway.com"},{"name":"","domain":"x.com"},
         {"name":"Bad","domain":"not a domain"},{"name":"A","domain":"a.com"},{"name":"B","domain":"b.com"},
         {"name":"C","domain":"c.com"},{"name":"D","domain":"d.com"},{"name":"E","domain":"e.com"}, 3]
        """
        let results = BrandSearch.parse(Data(body.utf8))
        #expect(results.first == BrandSearchResult(name: "Subway", domain: "subway.com"))
        #expect(results.count == BrandSearch.limit)
        #expect(BrandSearch.parse(Data("{}".utf8)).isEmpty)
    }

    @Test
    func brandfetchSearchAsksOnlyWhenOnAndLongEnough() async {
        let calls = Calls()
        let fetch: BrandfetchSearch.Fetch = { request in
            await calls.add(request.url?.absoluteString ?? "")
            let url = request.url ?? URL(fileURLWithPath: "/")
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil) ?? URLResponse()
            return (Data(#"[{"name":"Rappi","domain":"rappi.com"}]"#.utf8), response)
        }
        let on = BrandfetchSearch(configuration: BrandLogoConfiguration(isEnabled: true, clientID: "id"), fetch: fetch)
        let off = BrandfetchSearch(configuration: BrandLogoConfiguration(isEnabled: false, clientID: "id"), fetch: fetch)
        #expect(await on.search("Rappi") == [BrandSearchResult(name: "Rappi", domain: "rappi.com")])
        #expect(await on.search("R").isEmpty)
        #expect(await off.search("Rappi").isEmpty)
        #expect(await calls.all == ["https://api.brandfetch.io/v2/search/Rappi?c=id"])
    }
}

actor Calls {
    private(set) var all: [String] = []

    func add(_ call: String) {
        all.append(call)
    }
}

/// A brand search that answers at once and records what it was asked.
final class FakeBrandSearch: BrandSearching, @unchecked Sendable {
    private let lock = NSLock()
    private var asked: [String] = []
    let results: [BrandSearchResult]

    init(results: [BrandSearchResult]) {
        self.results = results
    }

    var queries: [String] {
        lock.withLock { asked }
    }

    func search(_ text: String) async -> [BrandSearchResult] {
        lock.withLock { asked.append(text) }
        return results
    }
}

/// The picker behind "Business" and "Via".
@Suite("Merchant picker")
@MainActor
struct MerchantPickerViewModelTests {
    private let subway = Merchant(name: "Subway", domain: "subway.com", brandID: "subway")
    private let uberEats = Merchant(name: "Uber Eats", domain: "ubereats.com", isPlatform: true)

    @Test
    func asksTheWebOnlyWhenNothingLocalMatchesAndShowsItsResults() async {
        let search = FakeBrandSearch(results: [BrandSearchResult(name: "Qwertz Café", domain: "qwertz.com")])
        var picked: MerchantChoice?
        let picker = MerchantPickerViewModel(
            role: .business, merchants: [subway, uberEats], current: nil, search: search, debounce: .zero,
        ) { picked = $0 }
        picker.query = "sub"
        await picker.waitForSearch()
        #expect(search.queries.isEmpty)
        #expect(picker.options.first?.choice == .merchant(subway.id))

        picker.query = "qwertz"
        await picker.waitForSearch()
        #expect(search.queries == ["qwertz"])
        let web = picker.options.first { $0.group == .web }
        #expect(web?.label == "Qwertz Café")
        #expect(web?.detail == "qwertz.com")
        // Picking hands over a merchant to create on save; nothing is created here.
        if let web {
            picker.pick(web)
        }
        #expect(picked == .new(MerchantDraft(name: "Qwertz Café", domain: "qwertz.com")))
    }

    @Test
    func withTheLogosOffTheWebIsNeverAsked() async {
        let picker = MerchantPickerViewModel(role: .business, merchants: [], current: nil, search: nil, debounce: .zero) { _ in }
        picker.query = "qwertz"
        await picker.waitForSearch()
        #expect(!picker.wantsRemote)
        #expect(picker.options.map(\.group) == [.new])
    }

    @Test
    func viaNeverOffersTheBusinessAndClearingHandsOverNil() {
        var picked: MerchantChoice? = .merchant(UUID())
        let picker = MerchantPickerViewModel(
            role: .via, merchants: [subway, uberEats], current: .merchant(uberEats.id), excluding: subway.id, search: nil,
        ) { picked = $0 }
        #expect(picker.options.map(\.label) == ["Uber Eats"])
        #expect(picker.currentName == "Uber Eats")
        picker.clear()
        #expect(picked == nil)
    }
}
