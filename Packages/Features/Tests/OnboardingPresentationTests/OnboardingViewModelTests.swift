import Domain
import DomainSamples
import Foundation
import OnboardingDomain
import Testing
@testable import OnboardingPresentation

struct CompleteOnboardingStub: CompleteOnboardingUseCase {
    var result: Result<Settings, DomainError> = .success(SampleData.standard.settings)
    let received = Received()

    final class Received: @unchecked Sendable {
        var draft: OnboardingDraft?
    }

    func execute(_ draft: OnboardingDraft) async throws(DomainError) -> Settings {
        received.draft = draft
        return try result.get()
    }
}

struct RestoreStub: RestoreFromBackupUseCase {
    var settings: Settings?

    func execute() async throws(DomainError) -> Settings? {
        settings
    }
}

final class NotificationsSpy: NotificationAuthorizing, @unchecked Sendable {
    private(set) var asked = false

    func requestAuthorization() async -> Bool {
        asked = true
        return true
    }
}

final class LanguageStub: LanguagePreference, @unchecked Sendable {
    let current: AppLanguage
    private(set) var hasChosen: Bool
    private(set) var saved: AppLanguage?

    init(current: AppLanguage = .english, hasChosen: Bool = true) {
        self.current = current
        self.hasChosen = hasChosen
    }

    func choose(_ language: AppLanguage) -> Bool {
        saved = language
        hasChosen = true
        return language != current
    }
}

@MainActor
enum OnboardingFactory {
    static func make(
        complete: CompleteOnboardingStub = CompleteOnboardingStub(),
        restore: RestoreStub = RestoreStub(),
        notifications: NotificationsSpy = NotificationsSpy(),
        language: LanguageStub = LanguageStub(),
    ) -> OnboardingViewModel {
        OnboardingViewModel(completeOnboarding: complete, restoreFromBackup: restore, notifications: notifications, language: language)
    }
}

@Suite("Onboarding view model")
@MainActor
struct OnboardingViewModelTests {
    @Test
    func startsWithNIOSelectedRateOneAndCashIncluded() {
        let viewModel = OnboardingFactory.make()
        #expect(viewModel.second == "NIO")
        #expect(viewModel.rateText == "1.0000")
        #expect(viewModel.rate == 1)
        #expect(viewModel.accounts.map(\.kind) == [.cash])
        #expect(viewModel.accounts.first?.currency == "NIO")
        #expect(viewModel.principalLabel == "USD · US Dollar")
    }

    @Test
    func choosingACurrencyResetsTheRate() {
        let viewModel = OnboardingFactory.make()
        viewModel.rateText = "36.6243"
        viewModel.selectSecond("EUR")
        #expect(viewModel.rateText == "1.0000")
        #expect(viewModel.accounts.first?.currency == "EUR")
    }

    @Test
    func nicaraguaExampleFillsTheRate() {
        let viewModel = OnboardingFactory.make()
        viewModel.selectSecond("MXN")
        viewModel.useNicaraguaExample()
        #expect(viewModel.second == "NIO")
        #expect(viewModel.rate == Decimal(string: "36.6243"))
        #expect(viewModel.rateSummary == "1 USD = 36.6243 NIO")
    }

    @Test
    func singleCurrencyHidesTheRateAndMovesCashToPrincipal() {
        let viewModel = OnboardingFactory.make()
        viewModel.selectSecond(nil)
        #expect(viewModel.rateSummary == nil)
        #expect(viewModel.currenciesSummary == "USD")
        #expect(viewModel.accounts.first?.currency == "USD")
        #expect(viewModel.canContinueFromCurrencies)
    }

    @Test
    func invalidRateBlocksContinuing() {
        let viewModel = OnboardingFactory.make()
        viewModel.rateText = "0"
        #expect(!viewModel.canContinueFromCurrencies)
        viewModel.rateText = "36,5"
        #expect(viewModel.rate == Decimal(string: "36.5"))
    }

    @Test
    func searchedCurrencyBecomesAnOption() {
        let viewModel = OnboardingFactory.make()
        viewModel.selectSecond("CRC")
        #expect(viewModel.secondCurrencyOptions.map(\.code).contains("CRC"))
        #expect(viewModel.secondCurrencyOptions.last?.label == "Single currency only")
    }

    @Test
    func principalCannotAlsoBeSecond() {
        let viewModel = OnboardingFactory.make()
        viewModel.selectPrincipal("NIO")
        #expect(viewModel.second == nil)
        #expect(!viewModel.secondCurrencyOptions.map(\.code).contains("NIO"))
    }

    @Test
    func accountsCanBeAddedEditedAndRemovedButCashStays() {
        let viewModel = OnboardingFactory.make()
        var bank = viewModel.newAccount(.bank)
        bank.name = "Savings"
        viewModel.save(bank)
        bank.balance = 100
        viewModel.save(bank)
        #expect(viewModel.accounts.count == 2)
        #expect(viewModel.accounts.last?.balance == 100)
        viewModel.removeAccount(id: bank.id)
        viewModel.removeAccount(id: viewModel.accounts[0].id)
        #expect(viewModel.accounts.map(\.kind) == [.cash])
    }

    @Test
    func stepsAdvanceInOrder() {
        let viewModel = OnboardingFactory.make()
        viewModel.start()
        viewModel.continueFromCurrencies()
        viewModel.continueFromAccounts()
        #expect(viewModel.path == [.currencies, .accounts, .privacy])
    }

    @Test
    func allowingNotificationsAsksThenSavesTheWholeDraft() async {
        let complete = CompleteOnboardingStub()
        let notifications = NotificationsSpy()
        let viewModel = OnboardingFactory.make(complete: complete, notifications: notifications)
        viewModel.useNicaraguaExample()
        viewModel.backsUpToICloud = false
        viewModel.path = [.currencies, .accounts, .privacy]
        await viewModel.allowNotifications()
        #expect(notifications.asked)
        #expect(complete.received.draft?.currencies.rate == Decimal(string: "36.6243"))
        #expect(complete.received.draft?.backsUpToICloud == false)
        #expect(viewModel.path.last == .done)
        #expect(viewModel.completedSettings != nil)
    }

    @Test
    func skippingNotificationsStillFinishes() async {
        let notifications = NotificationsSpy()
        let viewModel = OnboardingFactory.make(notifications: notifications)
        await viewModel.skipNotifications()
        #expect(!notifications.asked)
        #expect(viewModel.path.last == .done)
    }

    @Test
    func saveFailureShowsAMessageAndStays() async {
        let viewModel = OnboardingFactory.make(complete: CompleteOnboardingStub(result: .failure(.persistence("disk"))))
        viewModel.path = [.currencies, .accounts, .privacy]
        await viewModel.skipNotifications()
        #expect(viewModel.path.last == .privacy)
        #expect(viewModel.errorMessage != nil)
    }

    @Test
    func restoreReportsWhenNothingWasFound() async {
        let viewModel = OnboardingFactory.make()
        #expect(await viewModel.restore() == nil)
        #expect(viewModel.restoreState == .notFound)
        let found = OnboardingFactory.make(restore: RestoreStub(settings: SampleData.standard.settings))
        #expect(await found.restore() != nil)
        #expect(found.restoreState == .idle)
    }
}
