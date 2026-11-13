import Domain
import Foundation
import Observation
import SharedPresentation

/// Creates or edits one categorization rule: the text to look for, expense or income, the category
/// and optional tags. An existing rule can also be applied to past movements that are still
/// uncategorized or in "Other", after a confirmation that says how many.
@MainActor
@Observable
public final class RuleEditorViewModel: Identifiable {
    public let id = UUID()
    public var match: String
    public var kind: TransactionKind {
        didSet {
            if kind != oldValue {
                categoryID = nil
            }
        }
    }

    public var categoryID: String?
    public var tags: [String]
    public let tagUsage: [String]
    public private(set) var errorMessage: String?
    public private(set) var isSaving = false
    /// How many movements "Apply to past movements" would change, while its confirmation is up.
    public var pastMatchCount: Int?
    /// "3 movements are now in Transport." after applying.
    public private(set) var appliedMessage: String?

    private let editing: CategorizationRule?
    private let allCategories: [TransactionCategory]
    private let manage: any ManageCategorizationRulesUseCase

    public init(
        kind: TransactionKind = .expense,
        match: String = "",
        categories: [TransactionCategory],
        tagUsage: [String] = [],
        manage: any ManageCategorizationRulesUseCase,
    ) {
        editing = nil
        self.match = match
        self.kind = kind == .income ? .income : .expense
        tags = []
        allCategories = categories
        self.tagUsage = tagUsage
        self.manage = manage
    }

    public init(
        editing rule: CategorizationRule,
        categories: [TransactionCategory],
        tagUsage: [String] = [],
        manage: any ManageCategorizationRulesUseCase,
    ) {
        editing = rule
        match = rule.match
        kind = rule.kind
        categoryID = rule.categoryID
        tags = rule.tags
        allCategories = categories
        self.tagUsage = tagUsage
        self.manage = manage
    }

    public var isCreating: Bool {
        editing == nil
    }

    public var categories: [TransactionCategory] {
        TransactionCategory.ordered(allCategories).filter { $0.kind == kind }
    }

    public var categoryTitle: String {
        categories.first { $0.id == categoryID }.map(CategoryDisplay.name(of:)) ?? String(localized: "Choose", bundle: #bundle)
    }

    public var canSave: Bool {
        !match.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && categoryID != nil && !isSaving
    }

    /// Typing stops at the limit, like a category's name.
    public func setMatch(_ text: String) {
        match = String(text.prefix(CategorizationRule.maxMatchLength))
    }

    @discardableResult
    public func save() async -> CategorizationRule? {
        guard canSave, let categoryID else { return nil }
        isSaving = true
        defer { isSaving = false }
        do {
            let rule = try await manage.save(CategorizationRuleDraft(
                id: editing?.id, match: match, categoryID: categoryID, kind: kind, tags: tags,
                // The editor has no merchant field: the rule keeps the one it has.
                merchantID: editing?.merchantID,
            ))
            errorMessage = nil
            return rule
        } catch {
            errorMessage = String(localized: "We couldn't save the rule. Try again.", bundle: #bundle)
            return nil
        }
    }

    public var canDelete: Bool {
        editing != nil
    }

    public func delete() async -> Bool {
        guard let editing else { return false }
        do {
            try await manage.delete(id: editing.id)
            return true
        } catch {
            errorMessage = String(localized: "We couldn't delete the rule. Try again.", bundle: #bundle)
            return false
        }
    }

    // MARK: Apply to past movements

    /// Only a saved rule, as it is stored: unsaved edits apply once they're saved.
    public var canApplyToPast: Bool {
        editing != nil
    }

    /// Counts what the rule would change and asks; with nothing to change it says so instead.
    public func prepareApplyToPast() async {
        guard let editing else { return }
        appliedMessage = nil
        do {
            let count = try await manage.pastMatchCount(of: editing)
            if count == 0 {
                appliedMessage = String(localized: "No past movements to change.", bundle: #bundle)
            } else {
                pastMatchCount = count
            }
        } catch {
            errorMessage = String(localized: "We couldn't look at your movements. Try again.", bundle: #bundle)
        }
    }

    /// "Move 3 movements to Transport?".
    public var applyToPastTitle: String {
        let count = pastMatchCount ?? 0
        let category = editing.flatMap { rule in allCategories.first { $0.id == rule.categoryID } }
            .map(CategoryDisplay.name(of:)) ?? categoryTitle
        return String(localized: "Move \(count) movements to \(category)?", bundle: #bundle)
    }

    public func applyToPast() async {
        guard let editing else { return }
        pastMatchCount = nil
        do {
            let count = try await manage.applyToPast(editing)
            appliedMessage = String(localized: "\(count) movements updated.", bundle: #bundle)
        } catch {
            errorMessage = String(localized: "We couldn't update your movements. Try again.", bundle: #bundle)
        }
    }
}
