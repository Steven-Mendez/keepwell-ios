import Domain
import Foundation

public protocol CompleteOnboardingUseCase: Sendable {
    /// Saves settings, accounts and their payment methods; returns the stored settings.
    func execute(_ draft: OnboardingDraft) async throws(DomainError) -> Settings
}

public struct DefaultCompleteOnboardingUseCase: CompleteOnboardingUseCase {
    private let settings: any SettingsRepository
    private let accounts: any AccountRepository
    private let cards: any CardRepository
    private let backup: any BackupPreference
    private let now: @Sendable () -> Date

    public init(
        settings: any SettingsRepository,
        accounts: any AccountRepository,
        cards: any CardRepository,
        backup: any BackupPreference,
        now: @escaping @Sendable () -> Date = { .now },
    ) {
        self.settings = settings
        self.accounts = accounts
        self.cards = cards
        self.backup = backup
        self.now = now
    }

    public func execute(_ draft: OnboardingDraft) async throws(DomainError) -> Settings {
        let date = now()
        for accountDraft in draft.accounts {
            let (account, accountCards) = try Self.makeAccount(accountDraft, currencies: draft.currencies, date: date)
            try await accounts.save(account)
            for card in accountCards {
                try await cards.save(card)
            }
        }
        let result = Settings(
            currencies: draft.currencies,
            unlockMethod: draft.locksWithBiometrics ? .biometrics : .disabled,
            hidesAmountsInAppSwitcher: draft.hidesAmountsInAppSwitcher,
            isICloudBackupEnabled: draft.backsUpToICloud,
            hasCompletedOnboarding: true,
        )
        try await settings.save(result)
        backup.setICloudBackupEnabled(draft.backsUpToICloud)
        return result
    }

    static func makeAccount(
        _ draft: OnboardingAccountDraft,
        currencies: CurrencySettings,
        date: Date,
    ) throws(DomainError) -> (Account, [Card]) {
        guard draft.balance >= 0, draft.secondBalance >= 0 || draft.kind != .credit else { throw .invalidAmount }
        let id = draft.id
        let name = draft.name.trimmingCharacters(in: .whitespaces)
        switch draft.kind {
        case .cash:
            let account = Account(
                id: id,
                name: name,
                kind: .cash,
                openingBalances: [Money(draft.balance, draft.currency)],
                openingDate: date,
            )
            return (account, [])
        case .bank:
            let account = Account(
                id: id, name: name, bank: draft.bank, kind: .deposit,
                openingBalances: [Money(draft.balance, draft.currency)], openingDate: date,
            )
            // A bank account is its card, so it gets one even before the person gives its digits.
            return try (account, [
                Card.debit(for: id, lastFour: draft.lastFour, network: draft.network),
                Card(accountID: id, kind: .transfer),
            ])
        case .credit:
            let mode = currencies.second == nil ? .principal : (draft.debtMode ?? .dual)
            // Credit balances are debts, so they start negative (rule 5).
            let openingBalances: [Money] = switch mode {
            case .dual: [
                    Money(-draft.balance, currencies.principal),
                    Money(-draft.secondBalance, currencies.second ?? currencies.principal),
                ]
            case .principal: [Money(-draft.balance, currencies.principal)]
            case .second: [Money(-draft.balance, currencies.second ?? currencies.principal)]
            }
            let account = try Account(
                id: id, name: name, bank: draft.bank, kind: .credit,
                openingBalances: openingBalances, openingDate: date,
                creditTerms: CreditTerms(debtMode: mode),
            )
            let holder = try Card(
                accountID: id, kind: .creditHolder, network: draft.network,
                lastFour: draft.lastFour?.isEmpty == false ? draft.lastFour : nil, color: .azul,
            )
            return (account, [holder])
        }
    }
}
