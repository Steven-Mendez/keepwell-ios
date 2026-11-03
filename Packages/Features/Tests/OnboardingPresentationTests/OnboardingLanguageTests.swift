import Domain
import Testing
@testable import OnboardingPresentation

@Suite("Onboarding language")
@MainActor
struct OnboardingLanguageTests {
    @Test
    func asksOnlyUntilALanguageWasChosen() {
        #expect(OnboardingFactory.make(language: LanguageStub(hasChosen: false)).asksLanguage)
        #expect(!OnboardingFactory.make(language: LanguageStub(hasChosen: true)).asksLanguage)
    }

    @Test
    func startsOnTheLanguageOnScreen() {
        let viewModel = OnboardingFactory.make(language: LanguageStub(current: .spanish, hasChosen: false))
        #expect(viewModel.selectedLanguage == .spanish)
    }

    @Test
    func keepingTheLanguageOnScreenContinues() {
        let language = LanguageStub(current: .spanish, hasChosen: false)
        let viewModel = OnboardingFactory.make(language: language)
        viewModel.confirmLanguage()
        #expect(language.saved == .spanish)
        #expect(!viewModel.asksLanguage)
        #expect(viewModel.languageNeedingReopen == nil)
    }

    @Test
    func choosingAnotherLanguageAsksToReopen() {
        let language = LanguageStub(current: .spanish, hasChosen: false)
        let viewModel = OnboardingFactory.make(language: language)
        viewModel.selectedLanguage = .english
        viewModel.confirmLanguage()
        #expect(language.saved == .english)
        #expect(viewModel.languageNeedingReopen == .english)
        #expect(viewModel.asksLanguage)
    }
}
