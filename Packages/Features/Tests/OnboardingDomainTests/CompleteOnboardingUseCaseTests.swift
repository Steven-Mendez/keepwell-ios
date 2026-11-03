import Domain
import DomainSamples
import Foundation
import Testing
@testable import OnboardingDomain

final class BackupSpy: BackupPreference, @unchecked Sendable {
    private(set) var isICloudBackupEnabled = true

    func setICloudBackupEnabled(_ isEnabled: Bool) {
        isICloudBackupEnabled = isEnabled
    }
}

@Suite("Complete onboarding")
struct CompleteOnboardingUseCaseTests {
    private let date = Date(timeIntervalSince1970: 1_790_000_000)

    private func currencies() throws -> CurrencySettings {
        try CurrencySettings(principal: "USD", second: "NIO", rate: Decimal(string: "36.6243") ?? 1)
    }

    private func run(_ draft: OnboardingDraft) async throws -> (InMemoryStore, BackupSpy, Settings) {
        let store = InMemoryStore()
        let backup = BackupSpy()
        let useCase = DefaultCompleteOnboardingUseCase(settings: store, accounts: store, cards: store, backup: backup) { [date] in date }
        let settings = try await useCase.execute(draft)
        return (store, backup, settings)
    }

    @Test
    func savesFinishedSettingsAndBackupChoice() async throws {
        let draft = try OnboardingDraft(currencies: currencies(), accounts: [], locksWithBiometrics: false, backsUpToICloud: false)
        let (store, backup, settings) = try await run(draft)
        #expect(settings.hasCompletedOnboarding)
        #expect(settings.unlockMethod == .disabled)
        #expect(await store.load() == settings)
        #expect(!backup.isICloudBackupEnabled)
    }

    @Test
    func bankAccountGetsDebitAndTransferMethods() async throws {
        let bank = OnboardingAccountDraft(
            kind: .bank,
            name: "Ahorro",
            bank: "Banco Uno",
            currency: "USD",
            balance: 9443.6,
            lastFour: "1234",
        )
        let (store, _, _) = try await run(OnboardingDraft(currencies: currencies(), accounts: [bank]))
        let account = try #require(await store.fetchAccounts().first)
        #expect(account.kind == .deposit)
        #expect(account.openingBalances == [Money(9443.6, "USD")])
        #expect(account.openingDate == date)
        let cards = await store.fetchCards()
        #expect(cards.map(\.kind) == [.debit, .transfer])
        #expect(cards.first?.lastFour == "1234")
    }

    @Test
    func creditCardDebtStartsNegativeInBothCurrencies() async throws {
        let card = OnboardingAccountDraft(
            kind: .credit, name: "Mastercard", bank: "Banco Uno", currency: "USD",
            balance: 16.79, secondBalance: 197.02, lastFour: "4321", network: .mastercard, debtMode: .dual,
        )
        let (store, _, _) = try await run(OnboardingDraft(currencies: currencies(), accounts: [card]))
        let account = try #require(await store.fetchAccounts().first)
        #expect(account.openingBalances == [Money(-16.79, "USD"), Money(-197.02, "NIO")])
        #expect(account.creditTerms?.debtMode == .dual)
        #expect(await store.fetchCards().map(\.kind) == [.creditHolder])
    }

    @Test
    func singleCurrencyForcesPrincipalDebtMode() async throws {
        let card = OnboardingAccountDraft(kind: .credit, name: "Visa", currency: "USD", balance: 10, debtMode: .dual)
        let (store, _, _) = try await run(OnboardingDraft(currencies: CurrencySettings(), accounts: [card]))
        let account = try #require(await store.fetchAccounts().first)
        #expect(account.openingBalances == [Money(-10, "USD")])
        #expect(account.creditTerms?.debtMode == .principal)
    }

    @Test
    func cashAccountHasNoCards() async throws {
        let cash = OnboardingAccountDraft(kind: .cash, name: "Efectivo", currency: "NIO", balance: 560)
        let (store, _, _) = try await run(OnboardingDraft(currencies: currencies(), accounts: [cash]))
        #expect(await store.fetchAccounts().first?.kind == .cash)
        #expect(await store.fetchCards().isEmpty)
    }

    @Test
    func negativeBalancesAreRejected() async throws {
        let cash = OnboardingAccountDraft(kind: .cash, name: "Efectivo", currency: "NIO", balance: -1)
        await #expect(throws: DomainError.invalidAmount) {
            _ = try await run(OnboardingDraft(currencies: currencies(), accounts: [cash]))
        }
    }

    @Test
    func invalidLastFourIsRejected() async throws {
        let bank = OnboardingAccountDraft(kind: .bank, name: "Ahorro", currency: "USD", lastFour: "12")
        await #expect(throws: DomainError.invalidLastFour("12")) {
            _ = try await run(OnboardingDraft(currencies: currencies(), accounts: [bank]))
        }
    }

    @Test
    func displayNameJoinsBankAndName() {
        #expect(OnboardingAccountDraft(kind: .bank, name: "Ahorro", bank: "Banco Uno", currency: "USD").displayName == "Banco Uno Ahorro")
        #expect(OnboardingAccountDraft(kind: .cash, name: "Efectivo", currency: "NIO").displayName == "Efectivo")
    }
}

@Suite("Restore from backup")
struct RestoreFromBackupUseCaseTests {
    @Test
    func returnsFinishedSettingsAndTurnsBackupOn() async throws {
        var settings = SampleData.standard.settings
        settings.hasCompletedOnboarding = true
        let store = InMemoryStore(settings: settings)
        let backup = BackupSpy()
        backup.setICloudBackupEnabled(false)
        let restored = try await DefaultRestoreFromBackupUseCase(settings: store, backup: backup, attempts: 1).execute()
        #expect(restored == settings)
        #expect(backup.isICloudBackupEnabled)
    }

    @Test
    func givesUpWhenNothingArrives() async throws {
        let restored = try await DefaultRestoreFromBackupUseCase(
            settings: InMemoryStore(), backup: BackupSpy(), attempts: 2, interval: .milliseconds(1),
        ).execute()
        #expect(restored == nil)
    }
}
