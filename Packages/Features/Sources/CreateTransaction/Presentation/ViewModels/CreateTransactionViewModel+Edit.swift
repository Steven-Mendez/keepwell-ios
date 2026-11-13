import CreateTransactionDomain
import Domain
import Foundation
import SharedPresentation

/// Editing a saved movement and showing its receipt again: the fields come from the movement,
/// every step returns to the review, and saving keeps what the web keeps (id, rate, recurring rule).
extension CreateTransactionViewModel {
    /// "Always use Transport for “Uber”?", offered after an edit moves a movement to another
    /// category, as the web does after saving.
    public struct RuleOffer: Hashable, Sendable {
        public let match: String
        public let categoryID: String
        public let kind: TransactionKind
        public let title: String
    }

    public var isEditing: Bool {
        if case .edit = mode {
            return true
        }
        return false
    }

    /// Showing a stored receipt: "Log another" doesn't apply to it.
    public var isShowingStoredReceipt: Bool {
        if case .receipt = mode {
            return true
        }
        return false
    }

    /// "Edits keep the rate this transaction was logged with." under an edit that involves the
    /// second currency, so a changed rate in settings doesn't read as ignored.
    public var keepsRecordedRate: Bool {
        isEditing && original?.exchangeRate.hasSecondCurrency == true
    }

    func loadStored(_ id: UUID) async {
        guard let getStored, let stored = try? await getStored.execute(id: id) else {
            errorMessage = String(localized: "We couldn't load this movement.", bundle: #bundle)
            return
        }
        let transaction = stored.transaction
        original = transaction
        carriedDebitText = ""
        context = stored.context.forPickers(keeping: [stored.transaction.accountID, stored.transaction.destinationAccountID])
        type = MovementType(of: transaction, accounts: stored.context.accounts)
        movementID = transaction.id
        amountText = "\(transaction.amount)"
        currency = transaction.currency
        categoryPickedByPerson = true
        categoryID = transaction.categoryID
        source = transaction.cardID.map(PaymentSource.card) ?? .account(transaction.accountID)
        destinationAccountID = transaction.destinationAccountID
        description = transaction.description
        date = transaction.date
        // Only a movement in another currency carries one (`TransactionDraft(editing:)`).
        debitedText = TransactionDraft(editing: transaction).actualDebitedPrincipal.map { "\($0)" } ?? ""
        carriedDebitText = debitedText
        note = transaction.note ?? ""
        tags = transaction.tags
        isDraft = !transaction.isConfirmed
        if isShowingStoredReceipt {
            saved = stored.receipt
        }
    }

    /// Clears the charge an edit opened with once the amount or the currency changes, since the bank
    /// charged it for the old ones (the domain's `debitedFor`), so the screen shows what saving keeps.
    /// A charge the person typed stays.
    func clearStaleDebit(amountChanged: Bool, currencyChanged: Bool = false) {
        guard amountChanged || currencyChanged, !carriedDebitText.isEmpty, debitedText == carriedDebitText else { return }
        debitedText = ""
    }

    /// Whether two amount texts say the same amount ("24.5" and "24.50").
    static func sameAmount(_ first: String, _ second: String) -> Bool {
        let posix = Locale(identifier: "en_US_POSIX")
        guard let one = Decimal(string: first, locale: posix), let other = Decimal(string: second, locale: posix) else {
            return first.trimmingCharacters(in: .whitespaces) == second.trimmingCharacters(in: .whitespaces)
        }
        return one == other
    }

    /// "Save changes": stores the edit, then offers a rule when the category changed, or closes.
    public func saveChanges() async {
        guard isEditing, canSave, context != nil, let updateTransaction else { return }
        isSaving = true
        defer { isSaving = false }
        var draft = draft
        draft.isDraft = isDraft
        do {
            let result = try await updateTransaction.execute(draft)
            saved = result
            errorMessage = nil
            if let offer = ruleOffer(after: result.transaction) {
                ruleOffer = offer
            } else {
                finish(notice: String(localized: "Saved", bundle: #bundle))
            }
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    /// "Create rule": the movement's description, kind and new category become a rule.
    public func acceptRuleOffer() async {
        guard let offer = ruleOffer, let manageRules else { return }
        ruleOffer = nil
        do {
            try await manageRules.save(CategorizationRuleDraft(match: offer.match, categoryID: offer.categoryID, kind: offer.kind))
            finish(notice: String(localized: "Rule saved", bundle: #bundle))
        } catch {
            // The edit is already saved; the flow stays open so the person can try again.
            errorMessage = String(localized: "We couldn't save the rule. Try again.", bundle: #bundle)
        }
    }

    /// "Not now": the edit stands on its own.
    public func declineRuleOffer() {
        ruleOffer = nil
        finish(notice: String(localized: "Saved", bundle: #bundle))
    }

    /// Mirrors the web's `offerRule`: only for expenses and income whose category changed, with a
    /// description to match.
    private func ruleOffer(after transaction: Transaction) -> RuleOffer? {
        let match = transaction.description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard manageRules != nil, transaction.kind != .transfer, !match.isEmpty,
              let categoryID = transaction.categoryID, categoryID != original?.categoryID,
              let category = context?.categories.first(where: { $0.id == categoryID })
        else { return nil }
        let name = CategoryDisplay.name(of: category)
        return RuleOffer(
            match: match,
            categoryID: categoryID,
            kind: transaction.kind,
            title: String(localized: "Always use \(name) for “\(match)”?", bundle: #bundle),
        )
    }

    private func finish(notice: String) {
        completionNotice = notice
        isFinished = true
    }
}
