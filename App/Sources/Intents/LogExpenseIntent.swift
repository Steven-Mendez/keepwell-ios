import AppIntents
import Core
import CreateTransactionDomain
import DesignSystem
import Domain
import Foundation
import Persistence
import SharedPresentation
import SwiftUI

/// "Hey Siri, log a Restaurants expense from Cash in Keepwell": saves a confirmed expense without
/// opening the app, through the same use case and checks as the in-app flow. App Shortcut phrases
/// can only carry entities, never a number, so Siri always asks for the amount after the phrase.
struct LogExpenseIntent: AppIntent {
    static let title: LocalizedStringResource = "Log an expense"
    static let description = IntentDescription("Saves an expense in Keepwell with its amount, category and how you paid.")

    /// Optional so the system never fills in a placeholder: when it's missing, `perform` asks for it.
    /// The picker lists the currencies the app formats by name (it must be a compile-time list);
    /// `perform` still accepts only the person's own two.
    @Parameter(
        title: "Amount",
        currencyCodes: ["USD", "NIO", "EUR", "GBP", "CRC", "GTQ", "HNL", "MXN", "COP", "ARS", "CLP"],
        requestValueDialog: "How much did you spend?",
    )
    var amount: IntentCurrencyAmount?

    @Parameter(title: "Category")
    var category: ExpenseCategoryEntity?

    @Parameter(title: "Paid from")
    var account: PaymentAccountEntity?

    @Parameter(title: "Description")
    var detail: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$amount) in \(\.$category) from \(\.$account)") {
            \.$detail
        }
    }

    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let store = try await IntentStore.open()
        let context = DefaultGetTransactionContextUseCase(
            settings: store,
            categories: store,
            accounts: store,
            cards: store,
            transactions: store,
        )
        let current = try await context.execute()
        guard let amount, amount.amount > 0 else {
            throw $amount.needsValueError(Self.dialog(String(localized: "How much did you spend?")))
        }
        let currency = amount.currencyCode.uppercased()
        guard [current.currencies.principal, current.currencies.second].contains(currency) else {
            throw IntentFailure.unsupportedCurrency(currency)
        }
        guard let accountID = account?.id ?? Self.defaultAccount(in: current.accounts)?.id else {
            throw IntentFailure.noAccount
        }
        let categoryID = category?.id ?? TransactionCategory.otherExpenseID
        let categoryName = current.categories.first { $0.id == categoryID }.map(CategoryDisplay.name(of:)) ?? ""
        // A credit card pays with its plastic, so the expense lands on the debt of its currency.
        let holder = current.cards.first { $0.accountID == accountID && $0.kind == .creditHolder }
        let draft = TransactionDraft(
            kind: .expense,
            amount: amount.amount,
            currency: currency,
            categoryID: categoryID,
            source: holder.map { .card($0.id) } ?? .account(accountID),
            description: Self.description(detail) ?? category?.name ?? categoryName,
        )
        do {
            let saved = try await DefaultSaveTransactionUseCase(context: context, transactions: store).execute(draft)
            let spent = CurrencyFormatter().string(from: -saved.transaction.amount, currencyCode: saved.transaction.currency)
            let name = category?.name ?? categoryName
            let snippet = ExpenseSnippet(
                category: current.categories.first { $0.id == categoryID },
                categoryName: name,
                amount: spent,
                source: holder.map(CardDisplay.shortName(of:)) ?? CardDisplay.name(of: saved.account),
            )
            return .result(dialog: Self.dialog(String(localized: "Expense saved · \(name) \(spent)")), view: snippet)
        } catch {
            throw IntentFailure.notSaved
        }
    }

    /// Text resolved here, in the app's language. A resource handed to the system as-is comes back
    /// in English on Spanish iPhones, so runtime messages are passed as finished text.
    static func dialog(_ text: String) -> IntentDialog {
        IntentDialog(stringLiteral: text)
    }

    /// What the person said, or `nil` when they gave no description.
    static func description(_ spoken: String?) -> String? {
        let trimmed = spoken?.trimmingCharacters(in: .whitespaces) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Cash first, since quick spoken expenses are usually paid in cash; else the first account.
    static func defaultAccount(in accounts: [Account]) -> Account? {
        accounts.first { $0.kind == .cash } ?? accounts.first { $0.kind == .deposit }
    }
}

/// What Siri shows under its answer: the category's icon, the amount and what paid it, as the
/// receipt in the app does.
struct ExpenseSnippet: View {
    let category: TransactionCategory?
    let categoryName: String
    let amount: String
    let source: String

    var body: some View {
        HStack(spacing: KWSpacing.sm) {
            Image(systemName: CategoryDisplay.symbol(for: category))
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(CategoryDisplay.color(for: category))
                .frame(width: 40, height: 40)
                .background(CategoryDisplay.color(for: category).opacity(0.16), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(categoryName)
                    .font(.kw(15, weight: 600))
                Text(source)
                    .font(KWTextStyle.captionSm.font.weight(.regular))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(amount)
                .font(.kw(17, weight: 800))
                .monospacedDigit()
        }
        .padding(KWSpacing.md)
        .accessibilityElement(children: .combine)
    }
}

/// What Siri says when the expense can't be saved.
enum IntentFailure: Error, CustomLocalizedStringResourceConvertible {
    case unsupportedCurrency(String)
    case noAccount
    case notSaved

    var localizedStringResource: LocalizedStringResource {
        // Resolved here for the same reason as `LogExpenseIntent.dialog(_:)`.
        let text = switch self {
        case let .unsupportedCurrency(code): String(localized: "Keepwell only uses your two currencies, not \(code).")
        case .noAccount: String(localized: "Add an account in Keepwell first.")
        case .notSaved: String(localized: "Keepwell couldn't save the expense. Try again in the app.")
        }
        return LocalizedStringResource(stringLiteral: text)
    }
}

/// The store, opened for one intent. Intents can run while the app isn't open, so they can't rely
/// on the app's container; this opens the same store the app would.
enum IntentStore {
    static func open() async throws -> SwiftDataStore {
        let store = await StoreSelector.store(for: .current)
        return try SwiftDataStore(modelContainer: ModelContainerFactory.make(store: store))
    }
}

/// An expense category Siri and Shortcuts can offer.
struct ExpenseCategoryEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Category"
    static let defaultQuery = ExpenseCategoryQuery()

    let id: String
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct ExpenseCategoryQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [ExpenseCategoryEntity] {
        try await all().filter { identifiers.contains($0.id) }
    }

    func entities(matching string: String) async throws -> [ExpenseCategoryEntity] {
        try await all().filter { $0.name.localizedStandardContains(string) }
    }

    func suggestedEntities() async throws -> [ExpenseCategoryEntity] {
        try await all()
    }

    private func all() async throws -> [ExpenseCategoryEntity] {
        try await IntentStore.open().fetchCategories()
            .filter { $0.kind == .expense }
            .map { ExpenseCategoryEntity(id: $0.id, name: CategoryDisplay.name(of: $0)) }
    }
}

/// An account an expense can come out of: cash, a bank account or a credit card.
struct PaymentAccountEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Account"
    static let defaultQuery = PaymentAccountQuery()

    let id: UUID
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct PaymentAccountQuery: EntityStringQuery {
    func entities(for identifiers: [UUID]) async throws -> [PaymentAccountEntity] {
        try await all().filter { identifiers.contains($0.id) }
    }

    func entities(matching string: String) async throws -> [PaymentAccountEntity] {
        try await all().filter { $0.name.localizedStandardContains(string) }
    }

    func suggestedEntities() async throws -> [PaymentAccountEntity] {
        try await all()
    }

    private func all() async throws -> [PaymentAccountEntity] {
        let store = try await IntentStore.open()
        let cards = try await store.fetchCards()
        return try await store.fetchAccounts().map { account in
            // A credit card answers to how the person names the plastic ("Premia ··0633").
            let holder = cards.first { $0.accountID == account.id && $0.kind == .creditHolder }
            let name = account.kind == .credit ? holder.map(CardDisplay.shortName(of:)) ?? CardDisplay.name(of: account)
                : CardDisplay.name(of: account)
            return PaymentAccountEntity(id: account.id, name: name)
        }
    }
}

/// Phrases Siri and Spotlight offer without any setup.
struct KeepwellShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogExpenseIntent(),
            phrases: [
                "Log an expense in \(.applicationName)",
                "Log a \(\.$category) expense in \(.applicationName)",
                "Log an expense from \(\.$account) in \(.applicationName)",
            ],
            shortTitle: "Log expense",
            systemImageName: "plus.circle",
        )
    }
}
