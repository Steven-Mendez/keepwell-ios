import Core
import Domain
import Foundation
import Observation

/// Creates a category, or edits or deletes any of them, shipped defaults included. The kind comes
/// from where the editor opens (the movement being logged, or the settings tab), so it can't be
/// set to something the movement doesn't accept.
@MainActor
@Observable
public final class CategoryEditorViewModel: Identifiable {
    public let id = UUID()
    public let kind: TransactionKind
    /// `nil` while creating.
    public let editing: TransactionCategory?
    public var name: String
    public var icon: String
    /// `nil` keeps a default's own color until the person picks one.
    public var color: String?
    /// What "Other" of this kind is called now, for the delete confirmation.
    public let fallbackName: String
    /// The currency a budget is typed in. `nil` hides the budget field: without settings there
    /// is no principal to measure spending in.
    public let principalCurrency: String?
    /// The monthly budget as typed; empty means no budget.
    public var budgetText: String {
        didSet { errorMessage = nil }
    }

    public private(set) var errorMessage: String?
    public private(set) var isSaving = false

    private let saveCategory: any SaveCategoryUseCase
    private let deleteCategory: (any DeleteCategoryUseCase)?

    public init(
        kind: TransactionKind,
        name: String = "",
        principalCurrency: String? = nil,
        save: any SaveCategoryUseCase,
    ) {
        self.kind = kind
        editing = nil
        self.principalCurrency = principalCurrency
        budgetText = ""
        initialBudgetText = ""
        self.name = String(name.prefix(CategoryDraft.maxNameLength))
        icon = CategoryDisplay.symbolChoices.first ?? CategoryDisplay.fallbackSymbol
        color = CategoryDisplay.colorChoices.first
        fallbackName = CategoryDisplay.shippedFallbackName(for: kind)
        initialName = ""
        saveCategory = save
        deleteCategory = nil
    }

    public init(
        editing category: TransactionCategory,
        fallbackName: String? = nil,
        principalCurrency: String? = nil,
        save: any SaveCategoryUseCase,
        delete: any DeleteCategoryUseCase,
    ) {
        kind = category.kind
        editing = category
        self.principalCurrency = principalCurrency
        // A budget left in an old principal currency isn't shown as if it were in today's.
        let budgetText = category.monthlyBudget.flatMap { budget in
            budget.currency == principalCurrency ? CurrencyFormatter().number(budget.amount) : nil
        } ?? ""
        self.budgetText = budgetText
        initialBudgetText = budgetText
        // A default that still translates opens with the name the person reads, not the stored English.
        let shownName = CategoryDisplay.name(of: category)
        name = shownName
        initialName = shownName
        icon = CategoryDisplay.symbol(for: category)
        color = category.color
        self.fallbackName = fallbackName ?? CategoryDisplay.shippedFallbackName(for: category.kind)
        saveCategory = save
        deleteCategory = delete
    }

    private let initialName: String
    private let initialBudgetText: String

    public var isCreating: Bool {
        editing == nil
    }

    public var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSaving && isBudgetValid
    }

    /// Budgets cap spending, so only expense categories offer one.
    public var showsBudget: Bool {
        kind == .expense && principalCurrency != nil
    }

    /// Empty, or a positive amount.
    public var isBudgetValid: Bool {
        guard showsBudget else { return true }
        let trimmed = budgetText.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty || AmountInput.decimal(from: trimmed).map { $0 > 0 } == true
    }

    public var budgetFooter: String {
        String(localized: "Summary shows how much is left, and Home warns you at 80% and 100%.", bundle: #bundle)
    }

    /// Rewrites the typed budget with grouping and two decimals once the field loses focus.
    public func formatBudget() {
        if let formatted = AmountInput.formatted(budgetText) {
            budgetText = formatted
        }
    }

    /// "Other" receives the movements of deleted categories, so it can only be renamed.
    public var canDelete: Bool {
        guard let editing else { return false }
        return deleteCategory != nil && !editing.isFallback
    }

    public var isFallback: Bool {
        editing?.isFallback ?? false
    }

    /// Typing past the limit is cut here, so the field never shows text that won't be saved.
    public func setName(_ text: String) {
        name = String(text.prefix(CategoryDraft.maxNameLength))
        errorMessage = nil
    }

    /// What the tile looks like with the current choices, for the live preview.
    public var preview: TransactionCategory {
        TransactionCategory(id: editing?.id ?? "", name: name, kind: kind, icon: icon, color: color)
    }

    public func save() async -> TransactionCategory? {
        guard canSave else { return nil }
        isSaving = true
        defer { isSaving = false }
        do {
            let saved = try await saveCategory.execute(draft)
            errorMessage = nil
            return saved
        } catch {
            errorMessage = Self.message(for: error)
            return nil
        }
    }

    /// Leaving a translated default's name or icon untouched keeps them following the app: the
    /// name keeps translating and the icon keeps the shipped one.
    var draft: CategoryDraft {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let keepsName = editing?.translatesByID == true && trimmed == initialName
        let keepsIcon = editing.map { $0.icon == nil && icon == CategoryDisplay.symbol(for: $0) } ?? false
        return CategoryDraft(
            id: editing?.id,
            name: keepsName ? editing?.name ?? name : name,
            kind: kind,
            icon: keepsIcon ? nil : icon,
            color: color,
            monthlyBudget: monthlyBudget,
        )
    }

    /// An untouched field keeps the stored budget as it is, even one in an earlier principal
    /// currency that the field doesn't show.
    private var monthlyBudget: Money? {
        guard showsBudget, let principalCurrency else { return editing?.monthlyBudget }
        guard budgetText != initialBudgetText else { return editing?.monthlyBudget }
        return AmountInput.decimal(from: budgetText).map { Money($0, principalCurrency) }
    }

    public func delete() async -> Bool {
        guard canDelete, let editing, let deleteCategory else { return false }
        isSaving = true
        defer { isSaving = false }
        do {
            try await deleteCategory.execute(id: editing.id)
            return true
        } catch {
            errorMessage = String(localized: "We couldn't delete the category. Try again.", bundle: #bundle)
            return false
        }
    }

    static func message(for error: DomainError) -> String {
        switch error {
        case .missingName: String(localized: "Give the category a name.", bundle: #bundle)
        case .duplicateCategoryName: String(localized: "You already have a category with that name.", bundle: #bundle)
        default: String(localized: "We couldn't save the category. Try again.", bundle: #bundle)
        }
    }
}
