import Domain
import Foundation
import Observation
import SharedPresentation

/// Settings › Rules: "if it says Uber → Transport", in the order they're tried. The first rule a
/// new movement's description or note matches picks its category when the person hasn't.
@MainActor
@Observable
public final class RulesViewModel {
    public private(set) var rules: [CategorizationRule] = []
    public private(set) var categories: [TransactionCategory] = []
    public private(set) var errorMessage: String?
    public var editor: RuleEditorViewModel?
    public var isReordering = false
    private var tagUsage: [String] = []
    private var merchants: [Merchant] = []

    private let manage: any ManageCategorizationRulesUseCase
    private let getCategories: any GetCategoriesUseCase

    public init(manage: any ManageCategorizationRulesUseCase, getCategories: any GetCategoriesUseCase) {
        self.manage = manage
        self.getCategories = getCategories
    }

    public func load() async {
        do {
            rules = try await manage.rules()
            categories = try await getCategories.execute()
            tagUsage = try await manage.tagUsage()
            merchants = try await manage.merchants()
            errorMessage = nil
        } catch {
            errorMessage = String(localized: "We couldn't load your rules.", bundle: #bundle)
        }
    }

    /// "Transport", or "Deleted category" when the category it names is gone (it then does nothing).
    public func categoryName(of rule: CategorizationRule) -> String {
        category(of: rule).map(CategoryDisplay.name(of:)) ?? String(localized: "Deleted category", bundle: #bundle)
    }

    public func category(of rule: CategorizationRule) -> TransactionCategory? {
        categories.first { $0.id == rule.categoryID && $0.kind == rule.kind }
    }

    /// "Expense · #trabajo".
    public func detail(of rule: CategorizationRule) -> String {
        let kind = rule.kind == .income ? String(localized: "Income", bundle: #bundle) : String(localized: "Expenses", bundle: #bundle)
        return [kind, TagDisplay.line(rule.tags)].compactMap(\.self).joined(separator: " · ")
    }

    public func startNew() {
        editor = RuleEditorViewModel(categories: categories, tagUsage: tagUsage, merchants: merchants, manage: manage)
    }

    public func edit(_ rule: CategorizationRule) {
        editor = RuleEditorViewModel(editing: rule, categories: categories, tagUsage: tagUsage, merchants: merchants, manage: manage)
    }

    /// Called after the editor saved or deleted, so the list shows the stored result.
    public func editorFinished() async {
        editor = nil
        await load()
    }

    public func canMove(_ rule: CategorizationRule, by offset: Int) -> Bool {
        guard let index = rules.firstIndex(of: rule) else { return false }
        return rules.indices.contains(index + offset)
    }

    /// Moves one row up (`-1`) or down (`1`) and stores the new order, which decides the rule that wins.
    public func move(_ rule: CategorizationRule, by offset: Int) async {
        guard canMove(rule, by: offset), let index = rules.firstIndex(of: rule) else { return }
        let previous = rules
        // Shown at once, so tapping an arrow several times doesn't wait on storage.
        rules.swapAt(index, index + offset)
        do {
            try await manage.reorder(ids: rules.map(\.id))
            errorMessage = nil
        } catch {
            rules = previous
            errorMessage = String(localized: "We couldn't save the new order. Try again.", bundle: #bundle)
        }
    }
}
