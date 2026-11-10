import Domain
import DomainSamples
import Foundation
import Testing
@testable import OnboardingDomain

@Suite("Complete onboarding")
struct CompleteOnboardingUseCaseTests {
    private let date = Date(timeIntervalSince1970: 1_790_000_000)

    private func currencies() throws -> CurrencySettings {
        try CurrencySettings(principal: "USD", second: "NIO", rate: Decimal(string: "36.6243") ?? 1)
    }

    private func run(
        _ draft: OnboardingDraft,
        profile: InMemoryPasscodeStore = InMemoryPasscodeStore(),
    ) async throws -> (InMemoryStore, Settings) {
        let store = InMemoryStore()
        let useCase = DefaultCompleteOnboardingUseCase(
            settings: store, accounts: store, cards: store, profile: profile, passcodes: profile,
        ) { [date] in date }
        let settings = try await useCase.execute(draft)
        return (store, settings)
    }

    @Test
    func savesFinishedSettingsWithoutICloud() async throws {
        let draft = try OnboardingDraft(currencies: currencies(), accounts: [], locksWithBiometrics: false)
        let (store, settings) = try await run(draft)
        #expect(settings.hasCompletedOnboarding)
        #expect(settings.unlockMethod == .disabled)
        #expect(await store.load() == settings)
        #expect(!settings.isICloudBackupEnabled)
    }

    @Test
    func savesTheTrimmedNameForTheLockHomeAndCards() async throws {
        let profile = InMemoryPasscodeStore()
        var draft = try OnboardingDraft(currencies: currencies(), accounts: [])
        draft.preferredName = "  Steven \n"
        _ = try await run(draft, profile: profile)
        #expect(await profile.preferredName() == "Steven")
    }

    @Test
    func skippedNameLeavesNoName() async throws {
        let profile = InMemoryPasscodeStore(name: "Old")
        var draft = try OnboardingDraft(currencies: currencies(), accounts: [])
        draft.preferredName = "   "
        _ = try await run(draft, profile: profile)
        #expect(await profile.preferredName() == nil)
    }

    @Test(arguments: [
        (true, true, UnlockMethod.biometrics),
        (true, false, .biometrics),
        (false, true, .passcode),
        (false, false, .disabled),
    ])
    func lockFollowsFaceIDAndPasscodeChoices(biometrics: Bool, passcode: Bool, expected: UnlockMethod) async throws {
        let profile = try InMemoryPasscodeStore(passcode: passcode ? Passcode("135790") : nil)
        let draft = try OnboardingDraft(currencies: currencies(), accounts: [], locksWithBiometrics: biometrics, hasPasscode: passcode)
        let (_, settings) = try await run(draft, profile: profile)
        #expect(settings.unlockMethod == expected)
        #expect(await profile.hasPasscode() == passcode)
    }

    @Test
    func leftoverPasscodeIsRemovedWhenNoneWasCreated() async throws {
        let profile = try InMemoryPasscodeStore(passcode: Passcode("135790"))
        let draft = try OnboardingDraft(currencies: currencies(), accounts: [], hasPasscode: false)
        _ = try await run(draft, profile: profile)
        #expect(await profile.hasPasscode() == false)
    }

    @Test
    func bankAccountGetsDebitAndTransferMethods() async throws {
        let bank = OnboardingAccountDraft(
            kind: .bank,
            name: "Savings",
            bank: "Bank One",
            currency: "USD",
            balance: 9443.6,
            lastFour: "1234",
        )
        let (store, _) = try await run(OnboardingDraft(currencies: currencies(), accounts: [bank]))
        let account = try #require(await store.fetchAccounts().first)
        #expect(account.kind == .deposit)
        #expect(account.openingBalances == [Money(9443.6, "USD")])
        #expect(account.openingDate == date)
        let cards = await store.fetchCards()
        #expect(cards.map(\.kind) == [.debit, .transfer])
        #expect(cards.first?.lastFour == "1234")
    }

    @Test
    func bankAccountWithoutDigitsStillGetsItsCard() async throws {
        let bank = OnboardingAccountDraft(kind: .bank, name: "Savings", bank: "Bank One", currency: "USD", balance: 10)
        let (store, _) = try await run(OnboardingDraft(currencies: currencies(), accounts: [bank]))
        let cards = await store.fetchCards()
        #expect(cards.map(\.kind) == [.debit, .transfer])
        #expect(cards.first?.lastFour == nil)
    }

    @Test
    func creditCardDebtStartsNegativeInBothCurrencies() async throws {
        let card = OnboardingAccountDraft(
            kind: .credit, name: "Mastercard", bank: "Bank One", currency: "USD",
            balance: 16.79, secondBalance: 197.02, lastFour: "4321", network: .mastercard, debtMode: .dual,
        )
        let (store, _) = try await run(OnboardingDraft(currencies: currencies(), accounts: [card]))
        let account = try #require(await store.fetchAccounts().first)
        #expect(account.openingBalances == [Money(-16.79, "USD"), Money(-197.02, "NIO")])
        #expect(account.creditTerms?.debtMode == .dual)
        #expect(await store.fetchCards().map(\.kind) == [.creditHolder])
    }

    @Test
    func singleCurrencyForcesPrincipalDebtMode() async throws {
        let card = OnboardingAccountDraft(kind: .credit, name: "Visa", currency: "USD", balance: 10, debtMode: .dual)
        let (store, _) = try await run(OnboardingDraft(currencies: CurrencySettings(), accounts: [card]))
        let account = try #require(await store.fetchAccounts().first)
        #expect(account.openingBalances == [Money(-10, "USD")])
        #expect(account.creditTerms?.debtMode == .principal)
    }

    @Test
    func cashAccountHasNoCards() async throws {
        let cash = OnboardingAccountDraft(kind: .cash, name: "Cash", currency: "NIO", balance: 560)
        let (store, _) = try await run(OnboardingDraft(currencies: currencies(), accounts: [cash]))
        #expect(await store.fetchAccounts().first?.kind == .cash)
        #expect(await store.fetchCards().isEmpty)
    }

    @Test
    func negativeBalancesAreRejected() async throws {
        let cash = OnboardingAccountDraft(kind: .cash, name: "Cash", currency: "NIO", balance: -1)
        await #expect(throws: DomainError.invalidAmount) {
            _ = try await run(OnboardingDraft(currencies: currencies(), accounts: [cash]))
        }
    }

    @Test
    func invalidLastFourIsRejected() async throws {
        let bank = OnboardingAccountDraft(kind: .bank, name: "Savings", currency: "USD", lastFour: "12")
        await #expect(throws: DomainError.invalidLastFour("12")) {
            _ = try await run(OnboardingDraft(currencies: currencies(), accounts: [bank]))
        }
    }

    @Test
    func displayNameJoinsBankAndName() {
        #expect(OnboardingAccountDraft(kind: .bank, name: "Savings", bank: "Bank One", currency: "USD").displayName == "Bank One Savings")
        #expect(OnboardingAccountDraft(kind: .cash, name: "Cash", currency: "NIO").displayName == "Cash")
    }
}

/// Counts sync rounds as the coordinator would; `finishAfter` reads end a round.
private final class SyncRounds: @unchecked Sendable {
    private let lock = NSLock()
    private var reads = 0
    private let finishAfter: Int?

    init(finishAfter: Int?) {
        self.finishAfter = finishAfter
    }

    func completed() -> Int {
        lock.withLock {
            reads += 1
            guard let finishAfter else { return 0 }
            return reads > finishAfter ? 1 : 0
        }
    }
}

@Suite("Restore from the Keepwell account")
struct RestoreFromAccountUseCaseTests {
    @Test
    func anAccountWithDataBringsItsSettingsAndSkipsSetUp() async throws {
        var settings = SampleData.standard.settings
        settings.hasCompletedOnboarding = true
        let rounds = SyncRounds(finishAfter: nil)
        let restored = try await DefaultRestoreFromAccountUseCase(
            settings: InMemoryStore(settings: settings),
            hasUserData: { true },
            completedSyncRounds: { rounds.completed() },
            attempts: 1,
        ).execute()
        #expect(restored == settings)
    }

    /// Data whose settings never said onboarding was done (or never came) still opens home, now
    /// and on the next launch.
    @Test
    func dataWithoutFinishedSettingsIsMarkedAsSetUp() async throws {
        let store = InMemoryStore()
        let restored = try await DefaultRestoreFromAccountUseCase(
            settings: store, hasUserData: { true }, completedSyncRounds: { 0 }, attempts: 1,
        ).execute()
        #expect(restored?.hasCompletedOnboarding == true)
        #expect(try await store.load()?.hasCompletedOnboarding == true)
    }

    /// The reported bug: an account made elsewhere has finished settings and its categories, but
    /// nothing of the person's, and signing in skipped the name, currencies and accounts.
    @Test
    func finishedSettingsWithoutUserDataGoOnWithSetUp() async throws {
        var settings = SampleData.standard.settings
        settings.hasCompletedOnboarding = true
        let rounds = SyncRounds(finishAfter: 2)
        let restored = try await DefaultRestoreFromAccountUseCase(
            settings: InMemoryStore(settings: settings),
            hasUserData: { false },
            completedSyncRounds: { rounds.completed() },
            attempts: 1000,
            interval: .milliseconds(1),
        ).execute()
        #expect(restored == nil)
    }

    @Test
    func stopsWaitingOnceASyncRoundEndsWithNothing() async throws {
        let rounds = SyncRounds(finishAfter: 2)
        let restored = try await DefaultRestoreFromAccountUseCase(
            settings: InMemoryStore(), hasUserData: { false }, completedSyncRounds: { rounds.completed() },
            attempts: 1000, interval: .milliseconds(1),
        ).execute()
        #expect(restored == nil)
    }

    @Test
    func givesUpWhenSyncNeverAnswers() async throws {
        let rounds = SyncRounds(finishAfter: nil)
        let restored = try await DefaultRestoreFromAccountUseCase(
            settings: InMemoryStore(), hasUserData: { false }, completedSyncRounds: { rounds.completed() },
            attempts: 2, interval: .milliseconds(1),
        ).execute()
        #expect(restored == nil)
    }
}
