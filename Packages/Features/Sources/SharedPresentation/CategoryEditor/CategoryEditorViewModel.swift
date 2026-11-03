import Domain
import Foundation
import Observation

/// Creates one of the person's categories, or edits or deletes one they created. The kind comes
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
    public var color: String
    public private(set) var errorMessage: String?
    public private(set) var isSaving = false

    private let saveCategory: any SaveCategoryUseCase
    private let deleteCategory: (any DeleteCategoryUseCase)?

    public init(
        kind: TransactionKind,
        name: String = "",
        save: any SaveCategoryUseCase,
    ) {
        self.kind = kind
        editing = nil
        self.name = String(name.prefix(CategoryDraft.maxNameLength))
        icon = CategoryDisplay.symbolChoices.first ?? CategoryDisplay.fallbackSymbol
        color = CategoryDisplay.colorChoices.first ?? ""
        saveCategory = save
        deleteCategory = nil
    }

    public init(editing category: TransactionCategory, save: any SaveCategoryUseCase, delete: any DeleteCategoryUseCase) {
        kind = category.kind
        editing = category
        name = category.name
        icon = CategoryDisplay.symbol(for: category)
        color = category.color ?? CategoryDisplay.colorChoices.first ?? ""
        saveCategory = save
        deleteCategory = delete
    }

    public var isCreating: Bool {
        editing == nil
    }

    public var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSaving
    }

    public var canDelete: Bool {
        editing != nil && deleteCategory != nil
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
            let saved = try await saveCategory.execute(CategoryDraft(id: editing?.id, name: name, kind: kind, icon: icon, color: color))
            errorMessage = nil
            return saved
        } catch {
            errorMessage = Self.message(for: error)
            return nil
        }
    }

    public func delete() async -> Bool {
        guard let editing, let deleteCategory else { return false }
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
