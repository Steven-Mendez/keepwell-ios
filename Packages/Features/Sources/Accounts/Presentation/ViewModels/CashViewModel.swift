import AccountsDomain
import Core
import Domain
import Foundation
import Observation
import SharedPresentation

/// Drives a cash account's screen: its balance and movements, a new name and deleting it.
@MainActor
@Observable
public final class CashViewModel {
    public enum State: Equatable {
        case loading
        case loaded(CashDetail)
        case failed
        /// The account was deleted from this screen; there is nothing left to show.
        case deleted
    }

    public let accountID: UUID
    public private(set) var state = State.loading
    public private(set) var errorMessage: String?
    public private(set) var isSaving = false

    private let getDetail: any GetCashDetailUseCase
    private let renameAccount: any RenameAccountUseCase
    private let deleteAccount: any DeleteAccountUseCase
    private let formatter = CurrencyFormatter()

    public init(
        accountID: UUID,
        getDetail: any GetCashDetailUseCase,
        renameAccount: any RenameAccountUseCase,
        deleteAccount: any DeleteAccountUseCase,
    ) {
        self.accountID = accountID
        self.getDetail = getDetail
        self.renameAccount = renameAccount
        self.deleteAccount = deleteAccount
    }

    public var detail: CashDetail? {
        if case let .loaded(detail) = state {
            detail
        } else {
            nil
        }
    }

    public func load() async {
        guard state != .deleted else { return }
        do {
            state = try await .loaded(getDetail.execute(accountID: accountID))
        } catch {
            state = .failed
        }
    }

    public func clearError() {
        errorMessage = nil
    }

    /// Returns whether the sheet can close.
    public func rename(to name: String) async -> Bool {
        isSaving = true
        defer { isSaving = false }
        do {
            try await renameAccount.execute(accountID: accountID, name: name)
            errorMessage = nil
            await load()
            return true
        } catch {
            errorMessage = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? String(localized: "Write a name for the account.", bundle: #bundle)
                : Self.saveError
            return false
        }
    }

    /// Returns whether the account is gone, so the screen can close.
    public func delete() async -> Bool {
        isSaving = true
        defer { isSaving = false }
        do {
            try await deleteAccount.execute(accountID: accountID)
            errorMessage = nil
            state = .deleted
            return true
        } catch {
            errorMessage = Self.saveError
            return false
        }
    }

    private static var saveError: String {
        String(localized: "We couldn't save the change. Try again.", bundle: #bundle)
    }

    // MARK: - Display

    func balance(_ detail: CashDetail) -> String {
        formatter.string(detail.balance)
    }

    /// "≈ $12.00" when the cash is in the second currency.
    func equivalent(_ detail: CashDetail) -> String? {
        detail.principalEquivalent.map { "≈ \(formatter.string($0))" }
    }

    /// "Delete Wallet?"
    func deleteTitle(_ detail: CashDetail) -> String {
        let name = detail.account.name
        return String(localized: "Delete \(name)?", bundle: #bundle)
    }

    /// Says what goes with the account before the person confirms, including the transfers that
    /// reach other accounts, whose balances change too.
    func deleteMessage(_ detail: CashDetail) -> String {
        let count = detail.movementCount
        guard count > 0 else {
            return String(localized: "The account and its card are deleted. This can't be undone.", bundle: #bundle)
        }
        return String(
            localized: "The account, its card and its \(count) movements are deleted, including transfers with your other accounts, so their balances change too. This can't be undone.",
            bundle: #bundle,
        )
    }

    var display: TransactionDisplay? {
        detail.map { TransactionDisplay(accounts: $0.accounts, cards: $0.cards, categories: $0.categories) }
    }
}
