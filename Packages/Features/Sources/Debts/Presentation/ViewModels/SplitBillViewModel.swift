import Core
import DebtsDomain
import Domain
import Foundation
import Observation

/// "Split" on an expense: who shared it and how much each owes. Shares start equal between the
/// person and everyone added, and stay equal until one is edited by hand. An expense already split
/// shares only what is left (`load()`).
@MainActor
@Observable
public final class SplitBillViewModel: Identifiable {
    public struct Share: Identifiable, Hashable {
        public let id: UUID
        public var person: String
        public var amountText: String
    }

    public let id = UUID()
    public let transaction: Transaction
    public private(set) var shares: [Share] = []
    public private(set) var errorMessage: String?
    public private(set) var isSaving = false
    /// What is left to share: the whole expense until `load()` reads the earlier splits.
    public private(set) var remaining: Decimal
    /// Once a share is typed by hand, adding someone no longer rewrites the others.
    private var isEdited = false
    private let split: any SplitTransactionUseCase
    let formatter = CurrencyFormatter()

    public init(transaction: Transaction, split: any SplitTransactionUseCase) {
        self.transaction = transaction
        self.split = split
        remaining = transaction.amount
        addPerson()
    }

    /// Reads what earlier splits left, and starts the shares from it.
    public func load() async {
        guard let left = try? await split.remaining(of: transaction), left != remaining else { return }
        remaining = left
        if !isEdited {
            splitEqually()
        }
    }

    /// "Already split: C$100.00 left to share", once an earlier split took part of it.
    public var alreadySplit: String? {
        guard remaining < transaction.amount else { return nil }
        let left = formatter.string(from: remaining, currencyCode: transaction.currency)
        return String(localized: "Already split: \(left) left to share", bundle: #bundle)
    }

    public var total: String {
        formatter.string(from: transaction.amount, currencyCode: transaction.currency)
    }

    public var symbol: String {
        CurrencyFormatter.symbol(for: transaction.currency)
    }

    public func addPerson() {
        shares.append(Share(id: UUID(), person: "", amountText: ""))
        if !isEdited {
            splitEqually()
        }
    }

    public func remove(_ id: UUID) {
        guard shares.count > 1 else { return }
        shares.removeAll { $0.id == id }
        if !isEdited {
            splitEqually()
        }
    }

    public func setPerson(_ text: String, for id: UUID) {
        guard let index = shares.firstIndex(where: { $0.id == id }) else { return }
        shares[index].person = String(text.prefix(PersonalDebt.maxNameLength))
        errorMessage = nil
    }

    public func setAmount(_ text: String, for id: UUID) {
        guard let index = shares.firstIndex(where: { $0.id == id }), shares[index].amountText != text else { return }
        shares[index].amountText = text
        isEdited = true
        errorMessage = nil
    }

    /// Everyone, the person included, pays the same, rounded down to the cent.
    public func splitEqually() {
        let share = BillSplit.equalShare(of: remaining, people: shares.count)
        let text = formatter.number(share)
        for index in shares.indices {
            shares[index].amountText = text
        }
        isEdited = false
        errorMessage = nil
    }

    var amounts: [Decimal?] {
        shares.map { AmountInput.decimal(from: $0.amountText) }
    }

    /// "Your share: C$300.00", what is left for the person after the others' shares.
    public var yourShare: String {
        let others = amounts.compactMap(\.self).reduce(0, +)
        let mine = formatter.string(from: max(remaining - others, 0), currencyCode: transaction.currency)
        return String(localized: "Your share: \(mine)", bundle: #bundle)
    }

    public var canSave: Bool {
        !isSaving && shares.allSatisfy { !$0.person.trimmingCharacters(in: .whitespaces).isEmpty }
            && amounts.allSatisfy { ($0 ?? 0) > 0 }
    }

    public func save() async -> Bool {
        guard canSave else { return false }
        let values = amounts.compactMap(\.self)
        guard values.reduce(0, +) <= remaining else {
            errorMessage = String(localized: "The shares add up to more than the expense.", bundle: #bundle)
            return false
        }
        isSaving = true
        defer { isSaving = false }
        do {
            try await split.execute(
                transactionID: transaction.id,
                shares: zip(shares, values).map { SplitShare(person: $0.person, amount: $1) },
            )
            return true
        } catch {
            errorMessage = String(localized: "We couldn't split the expense. Try again.", bundle: #bundle)
            return false
        }
    }
}
