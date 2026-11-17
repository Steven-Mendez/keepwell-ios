import CreateTransactionDomain
import Domain
import Foundation
import SharedPresentation

/// The two ways to open the flow: logging a new movement, or a saved one to edit or show again.
extension CreateTransactionViewModel {
    public convenience init(
        getContext: any GetTransactionContextUseCase,
        save: any SaveTransactionUseCase,
        brandSearch: (any BrandSearching)? = nil,
        saveCategory: (any SaveCategoryUseCase)? = nil,
        receiptSaver: (any ReceiptImageSaving)? = nil,
        type: MovementType = .expense,
        calendar: Calendar = .current,
        now: @escaping () -> Date = { .now },
        makeID: @escaping () -> UUID = UUID.init,
    ) {
        self.init(
            mode: .create,
            useCases: UseCases(getContext: getContext, save: save, brandSearch: brandSearch),
            saveCategory: saveCategory,
            receiptSaver: receiptSaver,
            type: type,
            calendar: calendar,
            now: now,
            makeID: makeID,
        )
    }

    /// Edits a saved movement (`.edit`) or shows its receipt again (`.receipt`). The type and every
    /// field come from the movement once `load()` reads it.
    public convenience init(
        stored mode: Mode,
        getStored: any GetStoredTransactionUseCase,
        update: (any UpdateTransactionUseCase)? = nil,
        manageRules: (any ManageCategorizationRulesUseCase)? = nil,
        brandSearch: (any BrandSearching)? = nil,
        saveCategory: (any SaveCategoryUseCase)? = nil,
        receiptSaver: (any ReceiptImageSaving)? = nil,
        calendar: Calendar = .current,
        now: @escaping () -> Date = { .now },
    ) {
        self.init(
            mode: mode,
            useCases: UseCases(
                getStored: getStored,
                update: update,
                manageRules: manageRules,
                brandSearch: brandSearch,
            ),
            saveCategory: saveCategory,
            receiptSaver: receiptSaver,
            type: .expense,
            calendar: calendar,
            now: now,
            makeID: UUID.init,
        )
    }

    /// What saving and loading go through, by mode: creating uses the first two, a stored movement
    /// the rest.
    struct UseCases {
        var getContext: (any GetTransactionContextUseCase)?
        var save: (any SaveTransactionUseCase)?
        var getStored: (any GetStoredTransactionUseCase)?
        var update: (any UpdateTransactionUseCase)?
        var manageRules: (any ManageCategorizationRulesUseCase)?
        var brandSearch: (any BrandSearching)?
    }
}
