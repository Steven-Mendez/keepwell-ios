import Foundation

/// A business a movement was with ("Subway"), or a platform it went through ("Uber Eats", "Apple").
/// The person's own list, shared by movements, recurring rules and categorization rules, which point
/// at one by id. Created by hand, from a brand of the app's table (`brandID`) or from a brand search
/// (`domain`); its logo comes from `domain`, else from the brand's. keepwell-web ports it one to one
/// (`src/lib/domain/merchants.ts`).
public struct Merchant: Identifiable, Hashable, Sendable, Codable {
    public static let maxNameLength = 60
    /// As long as a brand id of the table may be on the wire.
    public static let maxBrandIDLength = 64

    public let id: UUID
    public let name: String
    /// A bare lowercase host name ("subway.com"), where its logo comes from.
    public let domain: String?
    /// The id of a brand in the app's brand table (`brands.json`) it was created from.
    public let brandID: String?
    /// The category a new movement with this business suggests when it has none yet.
    public let defaultCategoryID: String?
    /// A platform (delivery app, app store), offered first in "via".
    public let isPlatform: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        domain: String? = nil,
        brandID: String? = nil,
        defaultCategoryID: String? = nil,
        isPlatform: Bool = false,
    ) {
        self.id = id
        self.name = name
        self.domain = domain
        self.brandID = brandID
        self.defaultCategoryID = defaultCategoryID
        self.isPlatform = isPlatform
    }

    /// Whether the merchant could be stored as it is: a name, a domain that is one, ids in range.
    /// The shared fixtures (`entities.json`) check it against the web's schema.
    public var isWellFormed: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (domain.map(Merchants.isDomain) ?? true)
            && [brandID, defaultCategoryID].allSatisfy { id in id.map { (1 ... Self.maxBrandIDLength).contains($0.count) } ?? true }
    }
}

/// What a merchant editor or picker hands over; `id` is `nil` for a new one.
public struct MerchantDraft: Hashable, Sendable {
    public var id: UUID?
    public var name: String
    /// A web domain or address ("subway.com", "https://www.subway.com/en"); `nil` or blank for none.
    public var domain: String?
    /// A brand of the app's brand table it comes from.
    public var brandID: String?
    public var defaultCategoryID: String?
    /// `nil` keeps an edited merchant's, and is `false` for a new one.
    public var isPlatform: Bool?

    public init(
        id: UUID? = nil,
        name: String,
        domain: String? = nil,
        brandID: String? = nil,
        defaultCategoryID: String? = nil,
        isPlatform: Bool? = nil,
    ) {
        self.id = id
        self.name = name
        self.domain = domain
        self.brandID = brandID
        self.defaultCategoryID = defaultCategoryID
        self.isPlatform = isPlatform
    }
}

/// What a draft does with a movement's (or recurring rule's) link to a merchant. `keep` is what a
/// client older than merchants sends without knowing it: it never unlinks one.
public enum MerchantLink: Hashable, Sendable {
    /// The edited movement's link stays as it was (none for a new one).
    case keep
    /// No merchant: the draft clears it.
    case unlinked
    case merchant(UUID)
    /// One the person picked in the editor and that doesn't exist yet: saving the movement creates
    /// it (or reuses the equivalent one, `Merchants.equivalent`) in the same write.
    case new(MerchantDraft)

    public init(_ id: UUID?) {
        self = id.map(Self.merchant) ?? .unlinked
    }
}

public enum Merchants {
    /// The name as saved: trimmed, inner runs of spaces collapsed and cut to the limit.
    public static func name(_ text: String) -> String {
        let collapsed = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return String(collapsed.prefix(Merchant.maxNameLength)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Lowercase labels of letters, digits and hyphens, at least one dot, no scheme, path or port:
    /// a domain as Brandfetch knows a brand. The web's `MerchantDomain`.
    public static func isDomain(_ text: String) -> Bool {
        text.count <= 253
            && text.wholeMatch(of: /(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z][a-z0-9-]{0,61}[a-z0-9]/) != nil
    }

    /// A domain as saved: lowercase host name without scheme, `www.`, port, path or query
    /// ("https://www.Subway.com/en" → "subway.com"). `nil` when blank or not a domain.
    public static func normalizedDomain(_ text: String?) -> String? {
        guard let text else { return nil }
        var host = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        host = host.replacing(/^[a-z][a-z0-9+.\-]*:\/\//, with: "")
        host = host.replacing(/[\/?#].*$/, with: "")
        host = host.replacing(/:[0-9]+$/, with: "")
        host = host.replacing(/^www\./, with: "")
        host = host.replacing(/\.$/, with: "")
        guard !host.isEmpty, isDomain(host) else { return nil }
        return host
    }

    /// The comparison key "Café" and "CAFE" share.
    static func folded(_ text: String) -> String {
        CategorizationRules.folded(text)
    }

    /// The merchants by name, platforms not apart; equal names keep a stable order by id.
    public static func ordered(_ merchants: [Merchant]) -> [Merchant] {
        merchants.sorted { lhs, rhs in
            switch lhs.name.compare(rhs.name, options: [.caseInsensitive], locale: nil) {
            case .orderedAscending: true
            case .orderedDescending: false
            case .orderedSame: lhs.id.uuidString.lowercased() < rhs.id.uuidString.lowercased()
            }
        }
    }

    /// The merchants whose name has the query, without case or accents: names that start with it
    /// first, then the rest, each by name. An empty query lists them all.
    public static func search(_ merchants: [Merchant], query: String) -> [Merchant] {
        let needle = folded(query.trimmingCharacters(in: .whitespacesAndNewlines))
        let ordered = ordered(merchants)
        guard !needle.isEmpty else { return ordered }
        let starting = ordered.filter { folded($0.name).hasPrefix(needle) }
        let containing = ordered.filter { !folded($0.name).hasPrefix(needle) && folded($0.name).contains(needle) }
        return starting + containing
    }

    /// The choices for "via": platforms first, then the rest, never the business itself.
    public static func viaChoices(_ merchants: [Merchant], query: String, excluding merchantID: UUID? = nil) -> [Merchant] {
        let found = search(merchants, query: query).filter { $0.id != merchantID }
        return found.filter(\.isPlatform) + found.filter { !$0.isPlatform }
    }

    /// The merchant a draft names already, so picking a brand twice doesn't make two: the one from
    /// the same brand, else (for a draft without a brand) the one with the same domain, else the one
    /// with the same name, without case or accents.
    public static func equivalent(in merchants: [Merchant], to draft: MerchantDraft) -> Merchant? {
        if let brandID = draft.brandID {
            if let byBrand = merchants.first(where: { $0.brandID == brandID }) {
                return byBrand
            }
        } else if let domain = normalizedDomain(draft.domain),
                  let byDomain = merchants.first(where: { $0.domain == domain && $0.brandID == nil })
        {
            return byDomain
        }
        let wanted = folded(name(draft.name))
        guard !wanted.isEmpty else { return nil }
        return merchants.first { folded($0.name) == wanted }
    }

    /// The category a merchant suggests for a movement of this kind: its default, if it exists with
    /// that kind.
    public static func category(of merchant: Merchant?, kind: TransactionKind, categories: [TransactionCategory]) -> String? {
        guard let id = merchant?.defaultCategoryID, kind != .transfer else { return nil }
        return categories.contains { $0.id == id && $0.kind == kind } ? id : nil
    }

    /// Whether a merchant's default category is one that exists, and isn't for transfers.
    public static func isLiveDefaultCategory(_ id: String?, categories: [TransactionCategory]) -> Bool {
        guard let id else { return false }
        return categories.contains { $0.id == id && $0.kind != .transfer }
    }

    /// The merchant as saving stores it; throws for a blank name, a domain that isn't one or a newly
    /// chosen category that doesn't exist (or is for transfers).
    public static func validated(
        _ draft: MerchantDraft,
        id: UUID,
        categories: [TransactionCategory],
        current: Merchant? = nil,
    ) throws(DomainError) -> Merchant {
        let name = name(draft.name)
        guard !name.isEmpty else { throw .missingName }
        let domain = normalizedDomain(draft.domain)
        if domain == nil, !(draft.domain ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw .corruptedData("domain")
        }
        let brandID = draft.brandID?.trimmingCharacters(in: .whitespacesAndNewlines)
        var defaultCategoryID = draft.defaultCategoryID
        if let categoryID = defaultCategoryID {
            if let category = categories.first(where: { $0.id == categoryID }) {
                guard category.kind != .transfer else { throw .unsupportedTransactionKind(.transfer) }
            } else {
                // One the merchant already had and that is gone (deleted, or not pulled yet) is
                // dropped, so the merchant can still be saved; a newly chosen one must exist.
                guard categoryID == current?.defaultCategoryID else { throw .notFound(UUID(uuid: UUID_NULL)) }
                defaultCategoryID = nil
            }
        }
        return Merchant(
            id: id,
            name: name,
            domain: domain,
            brandID: brandID?.isEmpty == false ? brandID.map { String($0.prefix(Merchant.maxBrandIDLength)) } : nil,
            defaultCategoryID: defaultCategoryID,
            isPlatform: draft.isPlatform ?? current?.isPlatform ?? false,
        )
    }

    /// The links a draft saves: the edited item's where the draft keeps them, none where it says
    /// so, newly chosen ones only when they exist, and no platform that is the business itself. `known` is `nil`
    /// when the caller didn't load the merchants: the ids are taken as they are.
    public static func links(
        merchant: MerchantLink,
        via: MerchantLink,
        known merchants: [Merchant]?,
        existing: (merchantID: UUID?, viaMerchantID: UUID?)? = nil,
    ) -> (merchantID: UUID?, viaMerchantID: UUID?) {
        func resolved(_ link: MerchantLink, _ stored: UUID?) -> UUID? {
            // The id the edited item already had stays even when it isn't known here (a merchant
            // this device hasn't pulled yet): the person didn't change it. A newly chosen unknown one
            // is dropped; a link to a deleted merchant goes in the repair after a pull instead.
            let id: UUID? = switch link {
            case .keep: stored
            case .unlinked, .new: nil
            case let .merchant(id): id
            }
            return id.flatMap { id in id == stored || (merchants.map { $0.contains { $0.id == id } } ?? true) ? id : nil }
        }
        let business = resolved(merchant, existing?.merchantID)
        let platform = resolved(via, existing?.viaMerchantID)
        return (business, platform == business ? nil : platform)
    }

    /// The links with every `new` one resolved to a merchant: the equivalent one already saved (or
    /// created by the other link), else a new one, which `created` lists for saving in the same write
    /// as what names it.
    public static func creatingNew(
        _ links: [MerchantLink],
        in merchants: [Merchant],
        categories: [TransactionCategory],
        makeID: () -> UUID,
    ) throws(DomainError) -> (links: [MerchantLink], created: [Merchant]) {
        var known = merchants
        var created: [Merchant] = []
        var resolved: [MerchantLink] = []
        for link in links {
            guard case let .new(draft) = link else {
                resolved.append(link)
                continue
            }
            if let found = equivalent(in: known, to: draft) {
                resolved.append(.merchant(found.id))
                continue
            }
            var fresh = draft
            fresh.id = nil
            let merchant = try validated(fresh, id: makeID(), categories: categories)
            known.append(merchant)
            created.append(merchant)
            resolved.append(.merchant(merchant.id))
        }
        return (resolved, created)
    }

    /// The links with every one to `from` moved to `to` (or removed without one), and "via" dropped
    /// when it ends up naming the business itself. `nil` when nothing changes.
    public static func relinked(
        merchantID: UUID?,
        viaMerchantID: UUID?,
        from: UUID,
        to: UUID? = nil,
    ) -> (merchantID: UUID?, viaMerchantID: UUID?)? {
        guard merchantID == from || viaMerchantID == from else { return nil }
        let business = merchantID == from ? to : merchantID
        let via = viaMerchantID == from ? to : viaMerchantID
        return (business, via == business ? nil : via)
    }
}
