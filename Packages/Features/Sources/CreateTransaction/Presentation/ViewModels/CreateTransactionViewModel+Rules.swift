import CreateTransactionDomain
import Domain
import Foundation

/// Categorization rules ("if it says Uber → Transport") and tags while the movement is built.
extension CreateTransactionViewModel {
    /// "Category from rule: Uber" under the category, while a rule chose it.
    public var ruleHint: String? {
        appliedRule.map { String(localized: "Category from rule: \($0.match)", bundle: #bundle) }
    }

    /// Every tag used before, most used first, for the tag field's suggestions.
    public var tagUsage: [String] {
        context?.tagUsage ?? []
    }

    /// Follows the description and note: the first rule of this kind they match chooses the category
    /// and adds its tags, unless the person picked a category themselves (picking the catch-all
    /// "Other" still lets a rule decide). When the text stops matching, the earlier category and the
    /// rule's tags go back.
    func applyRules() {
        guard let context, !type.movesBetweenAccounts else { return }
        let mayChoose = !categoryPickedByPerson || appliedRule != nil || category?.isFallback == true
        guard mayChoose else { return }
        // The suggested description is the category's own name, not something the person typed.
        let typed = description == prefilledDescription ? "" : description
        let rule = CategorizationRules.firstMatch(in: context.rules, kind: kind, description: typed, note: note)
        guard rule != appliedRule else { return }
        if appliedRule == nil {
            categoryBeforeRule = categoryID
        }
        tags.removeAll { ruleAddedTags.contains($0) }
        if let rule {
            categoryID = rule.categoryID
            ruleAddedTags = rule.tags.filter { !tags.contains($0) }
            tags += ruleAddedTags
        } else {
            categoryID = categoryBeforeRule
            ruleAddedTags = []
        }
        appliedRule = rule
    }
}
