import Core
import DebtsDomain
import Domain
import Foundation
import Observation

/// "Split" on an expense: who shared it and how much each owes. A new split starts equal between the
/// person and everyone added, and stays equal until one is edited by hand. An expense already split
/// opens in "Edit split" (`load()`): its people with their shares, ready to change, remove or add to,
/// and the whole set is saved at once.
@MainActor
@Observable
public final class SplitBillViewModel: Identifiable {
    public struct Share: Identifiable, Hashable {
        public let id: UUID
        /// The debt this share already is; `nil` for someone added now.
        public var debtID: UUID?
        public var person: String
        public var amountText: String
        /// Settled, or owed in another currency (edited from Debts, where the currency shows): its
        /// amount stays as it is.
        public var isLocked = false
        public var isPaid = false
        /// A locked share's part of the expense, in the expense's currency.
        var lockedShare: Decimal?
        /// The currency a locked share is shown in.
        var currency: String?
    }

    public let id = UUID()
    public let transaction: Transaction
    public private(set) var shares: [Share] = []
    public private(set) var errorMessage: String?
    public private(set) var isSaving = false
    /// An expense already split: its shares are edited instead of split again.
    public private(set) var isEditing = false
    /// Once a share is typed by hand, adding someone no longer rewrites the others. An existing split
    /// starts that way: its amounts were chosen already.
    private var isEdited = false
    private let split: any SplitTransactionUseCase
    let formatter = CurrencyFormatter()

    public init(transaction: Transaction, split: any SplitTransactionUseCase) {
        self.transaction = transaction
        self.split = split
        addPerson()
    }

    /// Reads the shares already split from the expense; with any, the sheet edits them.
    public func load() async {
        guard let debts = try? await split.shares(of: transaction), !debts.isEmpty, !isEditing else { return }
        isEditing = true
        isEdited = true
        shares = debts.map { debt in
            let foreign = debt.amount.currency != transaction.currency
            let isLocked = foreign || debt.isSettled
            return Share(
                id: debt.id,
                debtID: debt.id,
                person: debt.person,
                amountText: formatter.number(debt.amount.amount),
                isLocked: isLocked,
                isPaid: debt.isSettled,
                lockedShare: isLocked ? (foreign ? debt.share(of: transaction, in: transaction.currency) ?? 0 : debt.amount.amount) : nil,
                currency: debt.amount.currency,
            )
        }
    }

    public var total: String {
        formatter.string(from: transaction.amount, currencyCode: transaction.currency)
    }

    public var symbol: String {
        CurrencyFormatter.symbol(for: transaction.currency)
    }

    /// A locked share as it reads: its amount in its own currency.
    public func lockedAmount(_ share: Share) -> String {
        formatter.string(from: AmountInput.decimal(from: share.amountText) ?? 0, currencyCode: share.currency ?? transaction.currency)
    }

    public func addPerson() {
        shares.append(Share(id: UUID(), person: "", amountText: ""))
        if !isEdited {
            splitEqually()
        }
    }

    /// Anyone can be removed from an existing split, down to no one (which removes the split); a new
    /// split keeps at least one row.
    public func remove(_ id: UUID) {
        guard isEditing || shares.count > 1 else { return }
        shares.removeAll { $0.id == id }
        errorMessage = nil
        if !isEdited {
            splitEqually()
        }
    }

    public var canRemove: Bool {
        isEditing || shares.count > 1
    }

    public func setPerson(_ text: String, for id: UUID) {
        guard let index = shares.firstIndex(where: { $0.id == id }) else { return }
        shares[index].person = String(text.prefix(PersonalDebt.maxNameLength))
        errorMessage = nil
    }

    public func setAmount(_ text: String, for id: UUID) {
        guard let index = shares.firstIndex(where: { $0.id == id }), !shares[index].isLocked,
              shares[index].amountText != text else { return }
        shares[index].amountText = text
        isEdited = true
        errorMessage = nil
    }

    private var lockedTotal: Decimal {
        shares.compactMap(\.lockedShare).reduce(0, +)
    }

    /// Everyone not locked, the person included, pays the same, rounded down to the cent.
    public func splitEqually() {
        let open = shares.indices.filter { !shares[$0].isLocked }
        let share = BillSplit.equalShare(of: max(transaction.amount - lockedTotal, 0), people: open.count)
        let text = formatter.number(share)
        for index in open {
            shares[index].amountText = text
        }
        isEdited = false
        errorMessage = nil
    }

    var amounts: [Decimal?] {
        shares.map { AmountInput.decimal(from: $0.amountText) }
    }

    private var others: Decimal {
        zip(shares, amounts).reduce(Decimal(0)) { sum, pair in
            sum + (pair.0.lockedShare ?? (pair.0.isLocked ? 0 : pair.1 ?? 0))
        }
    }

    /// "Your share: C$247.38 of C$1,156.25", what is left for the person after the others' shares.
    public var yourShare: String {
        let mine = formatter.string(from: max(transaction.amount - others, 0), currencyCode: transaction.currency)
        return String(localized: "Your share: \(mine) of \(total)", bundle: #bundle)
    }

    public var canSave: Bool {
        !isSaving && (isEditing || !shares.isEmpty)
            && shares.allSatisfy { !$0.person.trimmingCharacters(in: .whitespaces).isEmpty }
            && amounts.allSatisfy { ($0 ?? 0) > 0 }
    }

    public func save() async -> Bool {
        guard canSave else { return false }
        let values = amounts.compactMap(\.self)
        guard others <= transaction.amount else {
            errorMessage = String(localized: "The shares add up to more than the expense.", bundle: #bundle)
            return false
        }
        isSaving = true
        defer { isSaving = false }
        let edited = zip(shares, values).map { SplitShare(debtID: $0.debtID, person: $0.person, amount: $1) }
        do {
            if isEditing {
                try await split.save(transactionID: transaction.id, shares: edited)
            } else {
                try await split.execute(transactionID: transaction.id, shares: edited)
            }
            return true
        } catch {
            errorMessage = String(localized: "We couldn't split the expense. Try again.", bundle: #bundle)
            return false
        }
    }
}
