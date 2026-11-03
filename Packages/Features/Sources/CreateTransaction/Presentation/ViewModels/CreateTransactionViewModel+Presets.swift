import CreateTransactionDomain
import Foundation

/// Values the flow fills in for the person (a transfer's destination when paying a card, a widget's
/// category, the suggested description) and which payment methods it offers.
extension CreateTransactionViewModel {
    /// Starts a card payment already pointed at the card ("Pay" on a credit card): the accounts
    /// step opens with it chosen, and still offers the other cards.
    public func presetTransfer(to accountID: UUID) {
        type = .cardPayment
        presetDestinationID = accountID
    }

    /// Starts an expense in a category (a widget shortcut): after the amount it goes straight to
    /// the method, and going back still offers every category.
    public func presetCategory(_ categoryID: String) {
        presetCategoryID = categoryID
    }

    /// Shows the suggested description as real, editable text on the review step, as the design
    /// does. It follows the category while the person hasn't typed anything of their own.
    func prefillDescription() {
        let current = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard current.isEmpty || current == prefilledDescription else { return }
        description = descriptionPlaceholder
        prefilledDescription = description
    }

    /// Frozen cards and additional cards that don't allow the category can't pay; transfers can't
    /// leave from their own destination.
    public func isUsable(_ candidate: PaymentSource) -> Bool {
        guard let context else { return false }
        if case let .card(id) = candidate, let card = context.card(id) {
            guard !card.isFrozen else { return false }
            if let controls = card.additional, !controls.allows(categoryID: categoryID ?? "") {
                return false
            }
        }
        return kind != .transfer || context.accountID(for: candidate) != destinationAccountID
    }
}
