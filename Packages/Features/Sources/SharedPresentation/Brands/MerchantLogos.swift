import Domain
import Foundation

/// What a logo badge needs: the name its monogram comes from and the domain its logo is asked for.
/// Only a domain ever leaves the device: one from the app's brand table, or one a merchant was saved
/// with (from the brand table or Brandfetch's own search), never a description.
public struct LogoSubject: Hashable, Sendable {
    public let name: String
    public let domain: String

    public init(name: String, domain: String) {
        self.name = name
        self.domain = domain
    }

    public init(_ brand: Brand) {
        self.init(name: brand.name, domain: brand.domain)
    }

    /// The first letter or digit, which the badge shows before (or instead of) the logo.
    public var monogram: String {
        name.first { $0.isLetter || $0.isNumber }.map { String($0).uppercased() } ?? "·"
    }
}

/// keepwell-web's `presentation/merchants.ts`: where a merchant's or a movement's logo comes from,
/// and what the "Business" and "Via" pickers offer.
public enum MerchantLogos {
    public static func brand(id: String?, in brands: [Brand] = BrandCatalog.brands) -> Brand? {
        id.flatMap { id in brands.first { $0.id == id } }
    }

    /// A merchant's logo: its own domain, else its brand's. `nil` for a business without either.
    public static func logo(of merchant: Merchant, brands: [Brand] = BrandCatalog.brands) -> LogoSubject? {
        if let domain = merchant.domain {
            return LogoSubject(name: merchant.name, domain: domain)
        }
        return brand(id: merchant.brandID, in: brands).map { LogoSubject(name: merchant.name, domain: $0.domain) }
    }

    /// The logo a movement (or rule) shows: its merchant's first (domain, then brand), then the brand
    /// its description names, else none.
    public static func logo(
        description: String,
        merchant: Merchant?,
        brands: [Brand] = BrandCatalog.brands,
    ) -> LogoSubject? {
        if let merchant, let own = logo(of: merchant, brands: brands) {
            return own
        }
        return BrandCatalog.brand(for: description, in: brands).map(LogoSubject.init)
    }

    /// A recurring rule's logo: its own merchant's, else the brand its name names. A transfer is
    /// never a merchant, so it has none.
    public static func logo(of rule: RecurringRule, merchants: [Merchant], brands: [Brand] = BrandCatalog.brands) -> LogoSubject? {
        guard rule.kind != .transfer else { return nil }
        let merchant = rule.merchantID.flatMap { id in merchants.first { $0.id == id } }
        return logo(description: rule.name, merchant: merchant, brands: brands)
    }

    /// The merchant to create when the person picks a brand of the table.
    public static func draft(from brand: Brand) -> MerchantDraft {
        MerchantDraft(name: brand.name, domain: brand.domain, brandID: brand.id)
    }

    /// Brands of the table whose name or an alias starts a word with the query, the ones the person
    /// already has as a merchant left out; names that start with it first. At most `limit`.
    public static func brandSuggestions(
        _ query: String,
        merchants: [Merchant],
        limit: Int = 5,
        brands: [Brand] = BrandCatalog.brands,
    ) -> [Brand] {
        let needle = BrandCatalog.normalize(query)
        guard !needle.isEmpty else { return [] }
        let taken = Set(merchants.compactMap(\.brandID))
        func startsWord(_ text: String) -> Bool {
            " \(text)".contains(" \(needle)")
        }
        let ranked = brands.compactMap { brand -> (brand: Brand, rank: Int)? in
            guard !taken.contains(brand.id) else { return nil }
            let name = BrandCatalog.normalize(brand.name)
            if name.hasPrefix(needle) {
                return (brand, 0)
            }
            if startsWord(name) || brand.aliases.contains(where: startsWord) || brand.exactAliases.contains(needle) {
                return (brand, 1)
            }
            return nil
        }
        // A stable sort by rank keeps the table's order within each.
        return Array(ranked.enumerated().sorted { ($0.element.rank, $0.offset) < ($1.element.rank, $1.offset) }
            .map(\.element.brand).prefix(limit))
    }

    /// The business a new movement's description suggests: the person's merchant from the brand it
    /// names (or with that name), else that brand as a merchant to create. `nil` when it names no brand.
    public static func suggestedMerchant(
        for description: String,
        merchants: [Merchant],
        brands: [Brand] = BrandCatalog.brands,
    ) -> MerchantChoice? {
        guard let brand = BrandCatalog.brand(for: description, in: brands) else { return nil }
        let name = BrandCatalog.normalize(brand.name)
        let existing = merchants.first { $0.brandID == brand.id }
            ?? merchants.first { BrandCatalog.normalize($0.name) == name }
        return existing.map { .merchant($0.id) } ?? .new(draft(from: brand))
    }
}

/// What the "Business" or "Via" field holds: a saved merchant, or one to create when the movement is
/// saved.
public enum MerchantChoice: Hashable, Sendable {
    case merchant(UUID)
    case new(MerchantDraft)

    /// The merchant's name, or the one to create.
    public func name(in merchants: [Merchant]) -> String? {
        switch self {
        case let .merchant(id): merchants.first { $0.id == id }?.name
        case let .new(draft): draft.name
        }
    }

    /// Its logo, for a merchant to create too.
    public func logo(in merchants: [Merchant], brands: [Brand] = BrandCatalog.brands) -> LogoSubject? {
        switch self {
        case let .merchant(id):
            return merchants.first { $0.id == id }.flatMap { MerchantLogos.logo(of: $0, brands: brands) }
        case let .new(draft):
            let domain = Merchants.normalizedDomain(draft.domain) ?? MerchantLogos.brand(id: draft.brandID, in: brands)?.domain
            return domain.map { LogoSubject(name: draft.name, domain: $0) }
        }
    }

    public var merchantID: UUID? {
        if case let .merchant(id) = self {
            return id
        }
        return nil
    }
}

/// One line of a merchant picker.
public struct MerchantOption: Identifiable, Hashable, Sendable {
    public enum Group: Hashable, Sendable {
        /// The person's merchants.
        case mine
        /// The app's brand table.
        case brands
        /// Brandfetch's brand search.
        case web
        /// Creating it by hand with the typed name.
        case new
    }

    public let id: String
    public let label: String
    public let group: Group
    /// The domain a found brand comes with.
    public let detail: String?
    public let choice: MerchantChoice
    public let logo: LogoSubject?
}

public enum MerchantRole: Hashable, Sendable {
    case business
    case via
}

extension MerchantOption {
    static let maxMine = 6
    static let maxBrands = 4

    /// What a picker offers for the typed text: the person's merchants (platforms first for "via"),
    /// then the table's brands they don't have yet, then Brandfetch's results (`remote`) for domains
    /// not offered already, then creating it by hand when no merchant has that name. A merchant
    /// created from "via" is a platform.
    public static func options(
        query: String,
        merchants: [Merchant],
        remote: [BrandSearchResult] = [],
        role: MerchantRole = .business,
        excluding excludedID: UUID? = nil,
        brands: [Brand] = BrandCatalog.brands,
    ) -> [MerchantOption] {
        let isPlatform: Bool? = role == .via ? true : nil
        let mine = role == .via
            ? Merchants.viaChoices(merchants, query: query, excluding: excludedID)
            : Merchants.search(merchants, query: query).filter { $0.id != excludedID }
        var options = mine.prefix(maxMine).map { merchant in
            MerchantOption(
                id: "m:\(merchant.id)", label: merchant.name, group: .mine, detail: nil, choice: .merchant(merchant.id),
                logo: MerchantLogos.logo(of: merchant, brands: brands),
            )
        }
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return options }
        var offered = Set(merchants.compactMap(\.domain))
        for brand in MerchantLogos.brandSuggestions(text, merchants: merchants, limit: maxBrands, brands: brands) {
            offered.insert(brand.domain)
            var draft = MerchantLogos.draft(from: brand)
            draft.isPlatform = isPlatform
            let choice = MerchantChoice.new(draft)
            options.append(MerchantOption(
                id: "b:\(brand.id)", label: brand.name, group: .brands, detail: nil, choice: choice,
                logo: choice.logo(in: merchants, brands: brands),
            ))
        }
        for result in remote where offered.insert(result.domain).inserted {
            options.append(MerchantOption(
                id: "w:\(result.domain)", label: result.name, group: .web, detail: result.domain,
                choice: .new(MerchantDraft(name: result.name, domain: result.domain, isPlatform: isPlatform)),
                logo: LogoSubject(name: result.name, domain: result.domain),
            ))
        }
        let name = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let folded = CategorizationRules.folded(name)
        if !merchants.contains(where: { CategorizationRules.folded($0.name) == folded }) {
            options.append(MerchantOption(
                id: "n:\(name)", label: name, group: .new, detail: nil,
                choice: .new(MerchantDraft(name: name, isPlatform: isPlatform)), logo: nil,
            ))
        }
        return options
    }

    /// Brandfetch is asked only for a query long enough that matches none of the person's merchants
    /// or the table's brands.
    public static func needsBrandSearch(_ query: String, local: [MerchantOption]) -> Bool {
        BrandSearch.query(query) != nil && !local.contains { $0.group == .mine || $0.group == .brands }
    }
}
