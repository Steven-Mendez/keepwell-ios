import Domain
import Foundation
import Observation
import SharedPresentation

/// Settings › Businesses: the person's merchants (businesses and platforms), each opening an editor
/// to rename it, give it a default category, mark it as a platform, merge it into another or delete it.
@MainActor
@Observable
public final class MerchantsViewModel {
    public private(set) var merchants: [Merchant] = []
    public private(set) var categories: [TransactionCategory] = []
    public private(set) var movementCounts: [UUID: Int] = [:]
    public private(set) var errorMessage: String?
    public var editor: MerchantEditorViewModel?

    private let manage: any ManageMerchantsUseCase
    private let getCategories: any GetCategoriesUseCase

    public init(manage: any ManageMerchantsUseCase, getCategories: any GetCategoriesUseCase) {
        self.manage = manage
        self.getCategories = getCategories
    }

    public func load() async {
        do {
            merchants = try await manage.merchants()
            categories = try await getCategories.execute()
            movementCounts = try await manage.movementCounts()
            errorMessage = nil
        } catch {
            errorMessage = String(localized: "We couldn't load your businesses.", bundle: #bundle)
        }
    }

    /// "Platform · Restaurants · 12 movements".
    public func detail(of merchant: Merchant) -> String {
        let count = movementCounts[merchant.id] ?? 0
        return [
            merchant.isPlatform ? String(localized: "Platform", bundle: #bundle) : nil,
            categories.first { $0.id == merchant.defaultCategoryID }.map(CategoryDisplay.name(of:)),
            count == 1
                ? String(localized: "1 movement", bundle: #bundle)
                : String(localized: "\(count) movements", bundle: #bundle),
        ]
        .compactMap(\.self)
        .joined(separator: " · ")
    }

    public func logo(of merchant: Merchant) -> LogoSubject? {
        MerchantLogos.logo(of: merchant)
    }

    public func edit(_ merchant: Merchant) {
        editor = MerchantEditorViewModel(editing: merchant, merchants: merchants, categories: categories, manage: manage)
    }

    /// Called after the editor saved, merged or deleted, so the list shows the stored result.
    public func editorFinished() async {
        editor = nil
        await load()
    }
}

/// One merchant's editor.
@MainActor
@Observable
public final class MerchantEditorViewModel: Identifiable {
    public let merchant: Merchant
    public var name: String
    public var domain: String
    public var defaultCategoryID: String?
    public var isPlatform: Bool
    public private(set) var errorMessage: String?
    public private(set) var isWorking = false
    /// The other merchants this one can be merged into, by name.
    public let mergeTargets: [Merchant]
    /// Expense and income categories a default may be.
    public let categories: [TransactionCategory]

    private let manage: any ManageMerchantsUseCase

    public init(editing merchant: Merchant, merchants: [Merchant], categories: [TransactionCategory], manage: any ManageMerchantsUseCase) {
        self.merchant = merchant
        name = merchant.name
        domain = merchant.domain ?? ""
        defaultCategoryID = merchant.defaultCategoryID
        isPlatform = merchant.isPlatform
        mergeTargets = Merchants.ordered(merchants.filter { $0.id != merchant.id })
        self.categories = categories.filter { $0.kind != .transfer }
        self.manage = manage
    }

    public var canSave: Bool {
        !Merchants.name(name).isEmpty && !isWorking
    }

    public func categoryName(_ id: String?) -> String {
        categories.first { $0.id == id }.map(CategoryDisplay.name(of:)) ?? String(localized: "None", bundle: #bundle)
    }

    /// `true` once stored, so the sheet can close.
    public func save() async -> Bool {
        await run { () async throws(DomainError) in
            _ = try await manage.save(MerchantDraft(
                id: merchant.id,
                name: name,
                domain: domain,
                brandID: merchant.brandID,
                defaultCategoryID: defaultCategoryID,
                isPlatform: isPlatform,
            ))
        }
    }

    /// Everything that named this one names `target`, and this one goes.
    public func merge(into target: Merchant) async -> Bool {
        await run { () async throws(DomainError) in _ = try await manage.merge(merchant.id, into: target.id) }
    }

    /// Movements and rules that named it keep everything else.
    public func delete() async -> Bool {
        await run { () async throws(DomainError) in try await manage.delete(id: merchant.id) }
    }

    private func run(_ work: () async throws(DomainError) -> Void) async -> Bool {
        isWorking = true
        defer { isWorking = false }
        do {
            try await work()
            errorMessage = nil
            return true
        } catch {
            errorMessage = switch error {
            case .missingName: String(localized: "Give it a name.", bundle: #bundle)
            case .corruptedData: String(localized: "That isn't a web address, like subway.com.", bundle: #bundle)
            default: String(localized: "We couldn't save the business. Try again.", bundle: #bundle)
            }
            return false
        }
    }
}
