import DomainSamples
import Foundation
import Testing
@testable import Domain

/// Merchants: the shared fixture's cases, the names and domains saving stores, and the use cases
/// (create, save, delete, merge, repair after a pull), as keepwell-web's `tests/domain/merchants.test.ts`.
@Suite("Merchants")
struct MerchantTests {
    private let subway = Merchant(name: "Subway", domain: "subway.com", brandID: "subway", defaultCategoryID: "restaurants")
    private let uberEats = Merchant(name: "Uber Eats", domain: "ubereats.com", isPlatform: true)
    private let corner = Merchant(name: "Pulpería La Esquina")

    // MARK: Shared fixture (entities.json)

    private func fixture(_ entity: String) throws -> (valid: [[String: Any]], invalid: [[String: Any]]) {
        let url = try #require(Bundle.module.url(forResource: "entities", withExtension: "json", subdirectory: "Fixtures"))
        let file = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let cases = try #require((file["entities"] as? [String: Any])?[entity] as? [String: [[String: Any]]])
        return try (#require(cases["valid"]), #require(cases["invalid"]))
    }

    /// The web's `Merchant` schema, read field by field: `isPlatform` is required.
    private func merchant(_ value: [String: Any]) -> Merchant? {
        guard let id = (value["id"] as? String).flatMap(UUID.init(uuidString:)), let name = value["name"] as? String,
              let isPlatform = value["isPlatform"] as? Bool
        else { return nil }
        let merchant = Merchant(
            id: id, name: name, domain: value["domain"] as? String, brandID: value["brandId"] as? String,
            defaultCategoryID: value["defaultCategoryId"] as? String, isPlatform: isPlatform,
        )
        return merchant.isWellFormed ? merchant : nil
    }

    @Test
    func theFixtureMerchantsAreReadAsTheWebReadsThem() throws {
        let cases = try fixture("merchant")
        #expect(cases.valid.count == 3)
        for item in cases.valid {
            #expect(try merchant(#require(item["value"] as? [String: Any])) != nil, "\(item["name"] ?? "")")
        }
        #expect(cases.invalid.count == 4)
        for item in cases.invalid {
            #expect(try merchant(#require(item["value"] as? [String: Any])) == nil, "\(item["name"] ?? "")")
        }
    }

    /// Movements, recurring rules and categorization rules name merchants by id.
    @Test(arguments: ["transaction", "recurringRule", "categorizationRule"])
    func theFixtureLinksAreIDs(entity: String) throws {
        let cases = try fixture(entity)
        let linked = cases.valid.compactMap { $0["value"] as? [String: Any] }.filter { $0["merchantId"] != nil }
        #expect(!linked.isEmpty)
        for value in linked {
            #expect((value["merchantId"] as? String).flatMap(UUID.init(uuidString:)) != nil)
            if let via = value["viaMerchantId"] {
                #expect((via as? String).flatMap(UUID.init(uuidString:)) != nil)
            }
        }
        let bad = cases.invalid.filter { $0["name"] as? String == "merchant id that isn't an id" }
        #expect(bad.count == (entity == "recurringRule" ? 0 : 1))
        for item in bad {
            #expect(((item["value"] as? [String: Any])?["merchantId"] as? String).flatMap(UUID.init(uuidString:)) == nil)
        }
    }

    // MARK: Names and domains

    @Test(arguments: [
        ("https://www.Subway.com/en", "subway.com"),
        ("  UberEats.com  ", "ubereats.com"),
        ("http://shop.example.co.uk:8080/path?q=1", "shop.example.co.uk"),
        ("example.com.", "example.com"),
    ])
    func aDomainIsStoredAsABareHost(raw: String, expected: String) {
        #expect(Merchants.normalizedDomain(raw) == expected)
    }

    @Test(arguments: ["", "   ", "subway", "not a domain.com", "-bad.com"])
    func whatIsNotADomainIsDropped(raw: String) {
        #expect(Merchants.normalizedDomain(raw) == nil)
    }

    @Test
    func aNameIsTrimmedCollapsedAndCut() {
        #expect(Merchants.name("  Pulpería   La  Esquina ") == "Pulpería La Esquina")
        #expect(Merchants.name(String(repeating: "a", count: 80)).count == Merchant.maxNameLength)
    }

    @Test
    func searchPutsNamesThatStartWithTheQueryFirstAndViaPutsPlatformsFirst() {
        let all = [subway, uberEats, corner, Merchant(name: "Burger Sub")]
        #expect(Merchants.search(all, query: "sub").map(\.name) == ["Subway", "Burger Sub"])
        #expect(Merchants.search(all, query: "ESQUINA").map(\.name) == ["Pulpería La Esquina"])
        #expect(Merchants.viaChoices(all, query: "", excluding: subway.id).first == uberEats)
        #expect(!Merchants.viaChoices(all, query: "", excluding: subway.id).contains(subway))
    }

    @Test
    func theEquivalentMerchantIsTheSameBrandThenDomainThenName() {
        let byDomain = Merchant(name: "Mi Súper", domain: "lacolonia.com.ni")
        let all = [subway, byDomain, corner]
        #expect(Merchants.equivalent(in: all, to: MerchantDraft(name: "Subway Centro", brandID: "subway")) == subway)
        #expect(Merchants.equivalent(in: all, to: MerchantDraft(name: "La Colonia", domain: "https://www.lacolonia.com.ni")) == byDomain)
        #expect(Merchants.equivalent(in: all, to: MerchantDraft(name: "pulperia la esquina")) == corner)
        #expect(Merchants.equivalent(in: all, to: MerchantDraft(name: "Otra")) == nil)
    }

    // MARK: Links

    private func pair(_ links: (merchantID: UUID?, viaMerchantID: UUID?)) -> [UUID?] {
        [links.merchantID, links.viaMerchantID]
    }

    @Test
    func aDraftKeepsClearsOrSetsTheLinks() {
        let known = [subway, uberEats]
        let stored = (merchantID: Optional(subway.id), viaMerchantID: Optional(uberEats.id))
        // Left out keeps the edited movement's; an older client never unlinks one.
        #expect(pair(Merchants.links(merchant: .keep, via: .keep, known: known, existing: stored)) == [subway.id, uberEats.id])
        // Cleared on purpose.
        #expect(pair(Merchants.links(merchant: .unlinked, via: .keep, known: known, existing: stored)) == [nil, uberEats.id])
        #expect(pair(Merchants.links(merchant: .keep, via: .unlinked, known: known, existing: stored)) == [subway.id, nil])
        // A platform that is the business itself is dropped.
        #expect(pair(Merchants.links(merchant: .merchant(uberEats.id), via: .keep, known: known, existing: stored)) == [uberEats.id, nil])
    }

    @Test
    func aNewlyChosenUnknownMerchantIsDroppedButAStoredOneStays() {
        let ghost = UUID()
        #expect(Merchants.links(merchant: .merchant(ghost), via: .keep, known: [subway]).merchantID == nil)
        // The movement already named it (a merchant this device hasn't pulled yet): it stays.
        #expect(Merchants.links(merchant: .merchant(ghost), via: .keep, known: [subway], existing: (ghost, nil)).merchantID == ghost)
        #expect(Merchants.links(merchant: .keep, via: .keep, known: [], existing: (ghost, nil)).merchantID == ghost)
        // Without the merchants loaded the ids are taken as they come.
        #expect(Merchants.links(merchant: .merchant(ghost), via: .keep, known: nil).merchantID == ghost)
    }

    @Test
    func aMerchantPickedNewIsCreatedOnceOrReused() throws {
        var ids = [UUID(), UUID()].makeIterator()
        let resolved = try Merchants.creatingNew(
            [.new(MerchantDraft(name: "Subway", brandID: "subway")), .new(MerchantDraft(name: "Rappi", domain: "rappi.com"))],
            in: [subway],
            categories: TransactionCategory.defaults,
            makeID: { ids.next() ?? UUID() },
        )
        #expect(resolved.links.first == .merchant(subway.id))
        #expect(resolved.created.map(\.name) == ["Rappi"])
        #expect(resolved.created.first?.domain == "rappi.com")
    }

    // MARK: Rules

    @Test
    func aRuleSetsItsMerchantOnlyWhenTheMovementNamesNoneAndItIsLive() {
        let rule = CategorizationRule(match: "Subway", categoryID: "restaurants", kind: .expense, merchantID: subway.id)
        let movement = Fixtures.transaction(amount: "5")
        #expect(CategorizationRules.applying(rule, to: movement, merchants: [subway]).merchantID == subway.id)
        // Not a live merchant (deleted elsewhere, not repaired yet).
        #expect(CategorizationRules.applying(rule, to: movement, merchants: []).merchantID == nil)
        // The person cleared the business on purpose.
        #expect(CategorizationRules.applying(rule, to: movement, merchants: [subway], mayLinkMerchant: false).merchantID == nil)
        // One the person picked stays.
        let picked = movement.with(merchantID: corner.id, viaMerchantID: nil)
        #expect(CategorizationRules.applying(rule, to: picked, merchants: [subway, corner]).merchantID == corner.id)
        // The platform is never the business itself.
        let viaSubway = movement.with(merchantID: nil, viaMerchantID: subway.id)
        let applied = CategorizationRules.applying(rule, to: viaSubway, merchants: [subway])
        #expect(applied.merchantID == subway.id)
        #expect(applied.viaMerchantID == nil)
        #expect(applied.categoryID == "restaurants")
    }

    @Test
    func aRecurringOccurrenceCarriesTheRulesLinks() {
        let rule = RecurringRule(
            name: "iCloud+", kind: .expense, categoryID: "subscriptions", amount: 2.99, currency: "USD", accountID: UUID(),
            frequency: .monthly, startDate: Fixtures.date(2026, 11, 1), merchantID: subway.id, viaMerchantID: uberEats.id,
        )
        let movement = RecurringSchedule.movement(from: rule, on: rule.startDate, exchangeRate: Fixtures.usdNio)
        #expect(movement.merchantID == subway.id)
        #expect(movement.viaMerchantID == uberEats.id)
    }
}

/// The use cases over the in-memory store.
@Suite("Merchant use cases")
struct MerchantUseCaseTests {
    private let subway = Merchant(name: "Subway", domain: "subway.com", brandID: "subway", defaultCategoryID: "restaurants")
    private let uberEats = Merchant(name: "Uber Eats", domain: "ubereats.com", isPlatform: true)

    private func manage(_ store: InMemoryStore) -> DefaultManageMerchantsUseCase {
        DefaultManageMerchantsUseCase(
            merchants: store, categories: store, transactions: store, recurringRules: store, categorizationRules: store,
        )
    }

    private func linked(_ merchantID: UUID?, via: UUID?) -> Transaction {
        Fixtures.transaction(amount: "8").with(merchantID: merchantID, viaMerchantID: via)
    }

    @Test
    func createReusesTheEquivalentMerchant() async throws {
        let store = InMemoryStore(merchants: [subway])
        let again = try await manage(store).create(MerchantDraft(name: "SUBWAY", domain: "subway.com", brandID: "subway"))
        #expect(again == subway)
        let new = try await manage(store).create(MerchantDraft(name: "  Rappi ", domain: "https://www.Rappi.com/ni"))
        #expect(new.name == "Rappi")
        #expect(new.domain == "rappi.com")
        #expect(new.isPlatform == false)
        #expect(try await store.fetchMerchants().count == 2)
    }

    @Test
    func saveValidatesAndKeepsThePlatformFlagWhenLeftOut() async throws {
        let store = InMemoryStore(merchants: [uberEats])
        let manage = manage(store)
        await #expect(throws: DomainError.missingName) { try await manage.save(MerchantDraft(name: "  ")) }
        await #expect(throws: DomainError.corruptedData("domain")) {
            try await manage.save(MerchantDraft(name: "X", domain: "not a domain"))
        }
        await #expect(throws: DomainError.self) { try await manage.save(MerchantDraft(name: "X", defaultCategoryID: "nope")) }
        let renamed = try await manage.save(MerchantDraft(id: uberEats.id, name: "Uber Eats NI", domain: "ubereats.com"))
        #expect(renamed.isPlatform)
        #expect(renamed.name == "Uber Eats NI")
    }

    /// A default category that no longer exists is dropped when it is the stored one, and refused
    /// when newly chosen.
    @Test
    func aDeadDefaultCategoryIsDroppedOnlyWhenUnchanged() async throws {
        let stale = Merchant(name: "Viejo", defaultCategoryID: "gone")
        let store = InMemoryStore(merchants: [stale])
        let manage = manage(store)
        let saved = try await manage.save(MerchantDraft(id: stale.id, name: "Viejo", defaultCategoryID: "gone"))
        #expect(saved.defaultCategoryID == nil)
        await #expect(throws: DomainError.self) {
            try await manage.save(MerchantDraft(id: stale.id, name: "Viejo", defaultCategoryID: "also-gone"))
        }
    }

    @Test
    func deleteUnlinksEverywhereAndKeepsEverythingElse() async throws {
        let movement = linked(subway.id, via: uberEats.id)
        let viaOnly = linked(nil, via: subway.id)
        let recurring = RecurringRule(
            name: "Sub", kind: .expense, categoryID: "restaurants", amount: 5, currency: "USD", accountID: UUID(),
            frequency: .monthly, startDate: Fixtures.date(2026, 11, 1), tags: ["comida"], merchantID: subway.id,
        )
        let rule = CategorizationRule(match: "Subway", categoryID: "restaurants", kind: .expense, merchantID: subway.id)
        let store = InMemoryStore(
            transactions: [movement, viaOnly], recurringRules: [recurring], categorizationRules: [rule], merchants: [subway, uberEats],
        )
        try await manage(store).delete(id: subway.id)

        let movements = try await store.fetchTransactions(in: nil)
        #expect(movements.first { $0.id == movement.id }?.merchantID == nil)
        #expect(movements.first { $0.id == movement.id }?.viaMerchantID == uberEats.id)
        #expect(movements.first { $0.id == viaOnly.id }?.viaMerchantID == nil)
        #expect(try await store.fetchRecurringRules().first?.merchantID == nil)
        #expect(try await store.fetchRecurringRules().first?.tags == ["comida"])
        #expect(try await store.fetchCategorizationRules().first?.merchantID == nil)
        #expect(try await store.fetchMerchants() == [uberEats])
        await #expect(throws: DomainError.notFound(subway.id)) { try await manage(store).delete(id: subway.id) }
    }

    @Test
    func mergeRepointsFillsWhatIsMissingAndDeletesTheFirst() async throws {
        let duplicate = Merchant(
            name: "Subway Galerías",
            domain: "subway.com.ni",
            brandID: "subway",
            defaultCategoryID: "restaurants",
            isPlatform: true,
        )
        let bare = Merchant(name: "Subway")
        let both = linked(duplicate.id, via: bare.id)
        let rule = CategorizationRule(match: "Subway", categoryID: "restaurants", kind: .expense, merchantID: duplicate.id)
        let store = InMemoryStore(transactions: [both], categorizationRules: [rule], merchants: [duplicate, bare])
        let merged = try await manage(store).merge(duplicate.id, into: bare.id)

        #expect(merged.id == bare.id)
        #expect(merged.name == "Subway")
        #expect(merged.domain == "subway.com.ni")
        #expect(merged.brandID == "subway")
        #expect(merged.defaultCategoryID == "restaurants")
        #expect(merged.isPlatform)
        let movement = try #require(try await store.fetchTransactions(in: nil).first)
        // Both links now name the same merchant, so "via" goes.
        #expect(movement.merchantID == bare.id)
        #expect(movement.viaMerchantID == nil)
        #expect(try await store.fetchCategorizationRules().first?.merchantID == bare.id)
        #expect(try await store.fetchMerchants() == [merged])
    }

    /// Only a live, non-transfer default category is carried over, also over a dead one.
    @Test
    func mergeCarriesOnlyALiveDefaultCategory() async throws {
        let dead = Merchant(name: "A", defaultCategoryID: "gone")
        let live = Merchant(name: "B", defaultCategoryID: "groceries")
        let store = InMemoryStore(merchants: [dead, live])
        #expect(try await manage(store).merge(live.id, into: dead.id).defaultCategoryID == "groceries")

        let deadSource = Merchant(name: "C", defaultCategoryID: "gone")
        let empty = Merchant(name: "D")
        let other = InMemoryStore(merchants: [deadSource, empty])
        #expect(try await manage(other).merge(deadSource.id, into: empty.id).defaultCategoryID == nil)
    }

    @Test
    func movementCountsCountBusinessAndPlatformOnce() async throws {
        let store = InMemoryStore(
            transactions: [linked(subway.id, via: uberEats.id), linked(subway.id, via: nil)], merchants: [subway, uberEats],
        )
        let counts = try await manage(store).movementCounts()
        #expect(counts[subway.id] == 2)
        #expect(counts[uberEats.id] == 1)
    }

    @Test
    func theRepairAfterAPullUnlinksDeletedMerchants() async throws {
        let gone = UUID()
        let movement = linked(gone, via: uberEats.id)
        let untouched = linked(subway.id, via: nil)
        let rule = CategorizationRule(match: "X", categoryID: "restaurants", kind: .expense, merchantID: gone)
        let store = InMemoryStore(
            transactions: [movement, untouched], categorizationRules: [rule], merchants: [subway, uberEats],
        )
        let repair = DefaultUnlinkDeletedMerchantsUseCase(
            merchants: store, transactions: store, recurringRules: store, categorizationRules: store,
        )
        #expect(try await repair.execute(deletedMerchantIDs: []) == 0)
        #expect(try await repair.execute(deletedMerchantIDs: [gone]) == 2)
        let movements = try await store.fetchTransactions(in: nil)
        #expect(movements.first { $0.id == movement.id }?.merchantID == nil)
        #expect(movements.first { $0.id == movement.id }?.viaMerchantID == uberEats.id)
        #expect(movements.first { $0.id == untouched.id }?.merchantID == subway.id)
        #expect(try await store.fetchCategorizationRules().first?.merchantID == nil)
        #expect(try await repair.execute(deletedMerchantIDs: [gone]) == 0)
    }

    @Test
    func deletingACategoryClearsTheDefaultsThatNamedIt() async throws {
        let store = InMemoryStore(merchants: [subway, uberEats])
        try await DefaultDeleteCategoryUseCase(categories: store, transactions: store, merchants: store).execute(id: "restaurants")
        let merchants = try await store.fetchMerchants()
        #expect(merchants.first { $0.id == subway.id }?.defaultCategoryID == nil)
        #expect(merchants.first { $0.id == subway.id }?.name == "Subway")
    }

    @Test
    func theCategoryRepairAfterAPullClearsMerchantDefaults() async throws {
        let store = InMemoryStore(merchants: [subway, uberEats])
        let repair = DefaultReassignDeletedCategoriesUseCase(transactions: store, recurringRules: store, merchants: store)
        #expect(try await repair.execute(deletedCategoryIDs: ["restaurants"]) == 1)
        #expect(try await store.fetchMerchants().first { $0.id == subway.id }?.defaultCategoryID == nil)
        #expect(try await repair.execute(deletedCategoryIDs: ["restaurants"]) == 0)
    }

    @Test
    func applyingARuleToPastMovementsLinksOnlyLiveMerchants() async throws {
        let movement = Fixtures.transaction(amount: "5").with(categoryID: "other-expense", tags: [])
        let described = Transaction(
            id: movement.id, date: movement.date, description: "Subway centro", kind: .expense, categoryID: "other-expense",
            amount: 5, currency: "USD", accountID: movement.accountID, exchangeRate: Fixtures.usdNio,
        )
        let rule = CategorizationRule(match: "Subway", categoryID: "restaurants", kind: .expense, merchantID: subway.id)
        let store = InMemoryStore(transactions: [described], categorizationRules: [rule], merchants: [subway])
        let manageRules = DefaultManageCategorizationRulesUseCase(rules: store, categories: store, transactions: store, merchants: store)
        #expect(try await manageRules.applyToPast(rule) == 1)
        let applied = try #require(try await store.fetchTransactions(in: nil).first)
        #expect(applied.categoryID == "restaurants")
        #expect(applied.merchantID == subway.id)
        // A rule naming a merchant that isn't one is refused.
        await #expect(throws: DomainError.notFound(uberEats.id)) {
            try await manageRules.save(CategorizationRuleDraft(
                match: "Uber",
                categoryID: "transport",
                kind: .expense,
                merchantID: uberEats.id,
            ))
        }
    }
}
