import CreateTransactionDomain
import Domain
import Foundation
import SharedPresentation

/// Copy and navigation of the step headers, the review card and the receipt.
extension CreateTransactionViewModel {
    /// One end of the movement on the review card: what it is, and its balance afterwards.
    public struct Party: Hashable, Sendable {
        public let caption: String
        public let title: String
        public let detail: String?
        public let thumbnail: MethodRow.Thumbnail
    }

    // MARK: Steps

    /// (total, current) for the header's progress, per type: transfers have three steps.
    public func progress(of step: Step) -> (total: Int, current: Int) {
        let steps: [Step] = type.movesBetweenAccounts ? [.accounts, .amount, .review] : [.amount, .category, .method, .review]
        return (steps.count, (steps.firstIndex(of: step) ?? steps.count - 1) + 1)
    }

    public var typeTitle: String {
        Self.title(of: type)
    }

    public static func title(of type: MovementType) -> String {
        switch type {
        case .expense: String(localized: "Expense", bundle: #bundle)
        case .income: String(localized: "Income", bundle: #bundle)
        case .transfer: String(localized: "Between my accounts", bundle: #bundle)
        case .withdrawal: String(localized: "ATM withdrawal", bundle: #bundle)
        case .cardPayment: String(localized: "Card payment", bundle: #bundle)
        }
    }

    public var amountQuestion: String {
        switch type {
        case .expense: String(localized: "How much did you spend?", bundle: #bundle)
        case .income: String(localized: "How much did you receive?", bundle: #bundle)
        case .transfer: String(localized: "How much are you moving?", bundle: #bundle)
        case .withdrawal: String(localized: "How much did you withdraw?", bundle: #bundle)
        case .cardPayment: String(localized: "How much are you paying?", bundle: #bundle)
        }
    }

    public var amountButtonTitle: String {
        type.movesBetweenAccounts ? String(localized: "Review", bundle: #bundle) : String(localized: "Next", bundle: #bundle)
    }

    public var notePillTitle: String {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? String(localized: "Add a note", bundle: #bundle) : trimmed
    }

    public var sourceQuestion: String {
        switch type {
        case .withdrawal: String(localized: "Withdrawing from", bundle: #bundle)
        case .cardPayment: String(localized: "Paying from", bundle: #bundle)
        default: String(localized: "Moving from", bundle: #bundle)
        }
    }

    public var destinationQuestion: String {
        switch type {
        case .withdrawal: String(localized: "Which cash is it going into?", bundle: #bundle)
        case .cardPayment: String(localized: "Which card are you paying?", bundle: #bundle)
        default: String(localized: "Which account is it going to?", bundle: #bundle)
        }
    }

    // MARK: Review

    public var reviewTitle: String {
        switch type {
        case .expense, .income: String(localized: "You're about to log", bundle: #bundle)
        case .transfer: String(localized: "You're about to move", bundle: #bundle)
        case .withdrawal: String(localized: "You're about to withdraw", bundle: #bundle)
        case .cardPayment: String(localized: "You're about to pay", bundle: #bundle)
        }
    }

    public var confirmTitle: String {
        if isPlanned {
            return String(localized: "Slide to save as planned", bundle: #bundle)
        }
        return switch type {
        case .expense: String(localized: "Slide to save expense", bundle: #bundle)
        case .income: String(localized: "Slide to save income", bundle: #bundle)
        case .transfer: String(localized: "Slide to move", bundle: #bundle)
        case .withdrawal: String(localized: "Slide to withdraw", bundle: #bundle)
        case .cardPayment: String(localized: "Slide to pay", bundle: #bundle)
        }
    }

    /// Where the money comes from (or, for income, where it lands), with its balance afterwards.
    public var fromParty: Party? {
        guard let account = sourceAccount else { return nil }
        let caption = switch kind {
        case .expense: String(localized: "Paid with", bundle: #bundle)
        case .income: String(localized: "Into", bundle: #bundle)
        case .transfer: String(localized: "From", bundle: #bundle)
        }
        let title = type.movesBetweenAccounts ? CardDisplay.name(of: account) : sourceTitle ?? CardDisplay.name(of: account)
        let thumbnail: MethodRow.Thumbnail = if case let .card(id) = source, let card = context?.card(id), card.kind != .transfer {
            .card(card.color)
        } else {
            thumbnail(of: account)
        }
        return Party(caption: caption, title: title, detail: balanceAfter(preview?.sourceAfter, of: account), thumbnail: thumbnail)
    }

    public var toParty: Party? {
        guard type.movesBetweenAccounts, let account = destinationAccount else { return nil }
        return Party(
            caption: String(localized: "To", bundle: #bundle),
            title: CardDisplay.name(of: account),
            detail: balanceAfter(preview?.destinationAfter, of: account),
            thumbnail: thumbnail(of: account),
        )
    }

    /// The pencil next to the amount goes back to the keypad with everything else kept.
    public func editAmount() {
        path = rootStep == .amount ? [] : [.amount]
    }

    public func editSource() {
        path = type.movesBetweenAccounts ? [] : [.category, .method]
    }

    public func editCategory() {
        guard !type.movesBetweenAccounts else { return }
        path = [.category]
    }

    // MARK: Receipt

    public var receiptHeadline: String {
        switch type {
        case .expense: String(localized: "You spent", bundle: #bundle)
        case .income: String(localized: "You received", bundle: #bundle)
        case .transfer: String(localized: "You moved", bundle: #bundle)
        case .withdrawal: String(localized: "You withdrew", bundle: #bundle)
        case .cardPayment: String(localized: "You paid", bundle: #bundle)
        }
    }

    /// "Tuesday, November 3, 2026 at 9:22 AM", in the person's language.
    public func receiptDate(_ saved: SavedTransaction) -> String {
        saved.transaction.date.formatted(date: .complete, time: .shortened)
    }

    /// A short code to find the movement again, taken from its id.
    public func reference(_ saved: SavedTransaction) -> String {
        "KW-" + saved.transaction.id.uuidString.prefix(8).uppercased()
    }

    /// The plain-text receipt the share sheet sends.
    public func receiptText(_ saved: SavedTransaction) -> String {
        var lines = [
            "Keepwell · \(typeTitle)",
            receiptDate(saved),
            "",
            "\(receiptHeadline) \(formatter.string(Money(saved.transaction.amount, saved.transaction.currency)))",
            saved.transaction.description,
        ]
        if let fromParty {
            lines.append("\(fromParty.caption): \(fromParty.title)")
        }
        if let toParty {
            lines.append("\(toParty.caption): \(toParty.title)")
        }
        if let category, !type.movesBetweenAccounts {
            lines.append("\(String(localized: "Category", bundle: #bundle)): \(CategoryDisplay.name(of: category))")
        }
        if let note = saved.transaction.note {
            lines.append("\(String(localized: "Note", bundle: #bundle)): \(note)")
        }
        lines += savedRows(saved).map { "\($0.label): \($0.value)" }
        lines.append("\(String(localized: "Reference", bundle: #bundle)): \(reference(saved))")
        return lines.joined(separator: "\n")
    }

    /// "Arrived in Wallet · C$3,662.43" when the destination books another currency, so the
    /// receipt states both sides of the conversion.
    public var arrivedRow: Row? {
        guard type.movesBetweenAccounts, let account = destinationAccount, let arriving = preview?.arriving,
              arriving.currency != currency
        else { return nil }
        let name = CardDisplay.name(of: account)
        return Row(label: String(localized: "Arrived in \(name)", bundle: #bundle), value: "+" + formatter.string(arriving))
    }

    // MARK: Private

    private func balanceAfter(_ balances: [Money]?, of account: Account) -> String? {
        guard let balance = balance(of: account, in: balances) else { return nil }
        let amount = formatter.string(balance)
        return isPlanned
            ? String(localized: "Balance \(amount)", bundle: #bundle)
            : String(localized: "Balance after \(amount)", bundle: #bundle)
    }
}
