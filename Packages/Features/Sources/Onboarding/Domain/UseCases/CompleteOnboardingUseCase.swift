import Domain
import Foundation

public protocol CompleteOnboardingUseCase: Sendable {
    /// Saves settings, accounts and their payment methods, and the name; returns the stored settings.
    func execute(_ draft: OnboardingDraft) async throws(DomainError) -> Settings
}

public struct DefaultCompleteOnboardingUseCase: CompleteOnboardingUseCase {
    private let settings: any SettingsRepository
    private let accounts: any AccountRepository
    private let cards: any CardRepository
    private let profile: any ProfileRepository
    private let passcodes: any PasscodeRepository
    private let now: @Sendable () -> Date
    /// The device's zone, which becomes the home zone (`Settings.timeZone`) until changed in Settings.
    private let deviceTimeZone: @Sendable () -> String

    public init(
        settings: any SettingsRepository,
        accounts: any AccountRepository,
        cards: any CardRepository,
        profile: any ProfileRepository,
        passcodes: any PasscodeRepository,
        now: @escaping @Sendable () -> Date = { .now },
        deviceTimeZone: @escaping @Sendable () -> String = { TimeZone.current.identifier },
    ) {
        self.settings = settings
        self.accounts = accounts
        self.cards = cards
        self.profile = profile
        self.passcodes = passcodes
        self.now = now
        self.deviceTimeZone = deviceTimeZone
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
            unlockMethod: draft.unlockMethod,
            hidesAmountsInAppSwitcher: draft.hidesAmountsInAppSwitcher,
            // CloudKit is retired (increment 15); the field stays in the shared backup format.
            isICloudBackupEnabled: false,
            hasCompletedOnboarding: true,
            timeZone: HomeTimeZone.isWellFormed(deviceTimeZone()) ? deviceTimeZone() : nil,
        )
        try await settings.save(result)
        await profile.setPreferredName(PreferredName.normalized(draft.preferredName))
        // The Keychain outlives a reinstall, so a passcode from an earlier install (or an abandoned
        // onboarding) would otherwise lock the app with a code the person may not remember.
        if !draft.hasPasscode {
            await passcodes.removePasscode()
        }
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
