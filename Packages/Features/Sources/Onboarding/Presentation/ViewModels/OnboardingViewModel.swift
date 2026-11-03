import Core
import Domain
import Foundation
import Observation
import OnboardingDomain

/// Drives the onboarding steps. Holds the choices in memory and saves everything at once when
/// the person leaves the privacy step, so abandoning halfway leaves nothing behind.
@MainActor
@Observable
public final class OnboardingViewModel {
    public enum Step: Hashable, Sendable {
        case currencies
        case accounts
        case privacy
        case done
    }

    public enum RestoreState: Equatable, Sendable {
        case idle
        case searching
        case notFound
    }

    public struct CurrencyOption: Identifiable, Hashable, Sendable {
        /// `nil` is "Single currency only".
        public let code: String?
        public let label: String
        public var id: String { code ?? "single" }
    }

    /// Pushed steps after the welcome screen.
    public var path: [Step] = []
    public private(set) var principal = "USD"
    public private(set) var second: String? = "NIO"
    public var rateText = OnboardingViewModel.defaultRateText
    public private(set) var accounts: [OnboardingAccountDraft]
    public var locksWithBiometrics = true
    public var backsUpToICloud = true
    public var hidesAmountsInAppSwitcher = true
    public private(set) var restoreState = RestoreState.idle
    public private(set) var isSaving = false
    public private(set) var errorMessage: String?
    public private(set) var completedSettings: Settings?
    /// The language step shows first, once, until a language is picked.
    public private(set) var asksLanguage: Bool
    public var selectedLanguage: AppLanguage
    /// Set when the chosen language differs from the one on screen: iOS applies it on reopening.
    public private(set) var languageNeedingReopen: AppLanguage?
    private var searchedCurrencies: [String] = []

    private let completeOnboarding: any CompleteOnboardingUseCase
    private let restoreFromBackup: any RestoreFromBackupUseCase
    private let notifications: any NotificationAuthorizing
    private let language: any LanguagePreference

    static let defaultRateText = "1.0000"
    static let featuredSecondCurrencies = [
        ("NIO", String(localized: "Córdoba", bundle: #bundle)),
        ("MXN", String(localized: "Peso", bundle: #bundle)),
        ("COP", String(localized: "Peso", bundle: #bundle)),
        ("EUR", String(localized: "Euro", bundle: #bundle)),
    ]

    public init(
        completeOnboarding: any CompleteOnboardingUseCase,
        restoreFromBackup: any RestoreFromBackupUseCase,
        notifications: any NotificationAuthorizing,
        language: any LanguagePreference,
    ) {
        self.completeOnboarding = completeOnboarding
        self.restoreFromBackup = restoreFromBackup
        self.notifications = notifications
        self.language = language
        selectedLanguage = language.current
        asksLanguage = !language.hasChosen
        accounts = [OnboardingAccountDraft(kind: .cash, name: String(localized: "Cash", bundle: #bundle), currency: "NIO")]
    }

    // MARK: Currencies

    public var secondCurrencyOptions: [CurrencyOption] {
        let featured = Self.featuredSecondCurrencies
            .filter { $0.0 != principal }
            .map { CurrencyOption(code: $0.0, label: "\($0.0) · \($0.1)") }
        let searched = searchedCurrencies
            .filter { code in code != principal && !featured.contains { $0.code == code } }
            .map { CurrencyOption(code: $0, label: "\($0) · \(Self.shortName(for: $0))") }
        return featured + searched + [CurrencyOption(code: nil, label: String(localized: "Single currency only", bundle: #bundle))]
    }

    public var principalLabel: String {
        "\(principal) · \(Self.fullName(for: principal))"
    }

    /// The rate the person typed; must be positive.
    public var rate: Decimal? {
        AmountInput.decimal(from: rateText).flatMap { $0 > 0 ? $0 : nil }
    }

    public var canContinueFromCurrencies: Bool {
        second == nil || rate != nil
    }

    public func selectPrincipal(_ code: String) {
        principal = code
        if second == code {
            second = nil
        }
        rateText = Self.defaultRateText
        syncCashCurrency()
    }

    /// Choosing a currency resets the rate to 1, as the design does: the old rate belonged to
    /// another currency.
    public func selectSecond(_ code: String?) {
        if let code, !Self.featuredSecondCurrencies.contains(where: { $0.0 == code }), !searchedCurrencies.contains(code) {
            searchedCurrencies.append(code)
        }
        second = code
        rateText = Self.defaultRateText
        syncCashCurrency()
    }

    public func useNicaraguaExample() {
        selectSecond("NIO")
        rateText = "36.6243"
    }

    // MARK: Accounts

    public func newAccount(_ kind: OnboardingAccountDraft.Kind) -> OnboardingAccountDraft {
        switch kind {
        case .bank: OnboardingAccountDraft(kind: .bank, name: "", currency: principal)
        case .credit: OnboardingAccountDraft(
                kind: .credit,
                name: "",
                currency: principal,
                network: .visa,
                debtMode: second == nil ? .principal : .dual,
            )
        case .cash: accounts.first { $0.kind == .cash } ?? OnboardingAccountDraft(
                kind: .cash,
                name: String(localized: "Cash", bundle: #bundle),
                currency: second ?? principal,
            )
        }
    }

    public func save(_ account: OnboardingAccountDraft) {
        if let index = accounts.firstIndex(where: { $0.id == account.id }) {
            accounts[index] = account
        } else {
            accounts.append(account)
        }
    }

    public func removeAccount(id: UUID) {
        accounts.removeAll { $0.id == id && $0.kind != .cash }
    }

    // MARK: Language

    public var languages: [AppLanguage] {
        AppLanguage.allCases
    }

    public func confirmLanguage() {
        if language.choose(selectedLanguage) {
            languageNeedingReopen = selectedLanguage
        } else {
            asksLanguage = false
        }
    }

    // MARK: Navigation

    public func start() {
        path = [.currencies]
    }

    public func continueFromCurrencies() {
        guard canContinueFromCurrencies else { return }
        path.append(.accounts)
    }

    public func continueFromAccounts() {
        path.append(.privacy)
    }

    public func allowNotifications() async {
        _ = await notifications.requestAuthorization()
        await finish()
    }

    public func skipNotifications() async {
        await finish()
    }

    /// Returns restored settings when a backup arrived; the caller then leaves onboarding.
    public func restore() async -> Settings? {
        restoreState = .searching
        let restored = try? await restoreFromBackup.execute()
        restoreState = restored == nil ? .notFound : .idle
        return restored
    }

    // MARK: Done summary

    public var currenciesSummary: String {
        [principal, second].compactMap(\.self).joined(separator: " + ")
    }

    public var rateSummary: String? {
        guard let second, let rate else { return nil }
        return "1 \(principal) = \(rate) \(second)"
    }

    // MARK: Private

    private func finish() async {
        guard !isSaving, let currencies = try? CurrencySettings(principal: principal, second: second, rate: rate ?? 1) else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        let draft = OnboardingDraft(
            currencies: currencies,
            accounts: accounts,
            locksWithBiometrics: locksWithBiometrics,
            backsUpToICloud: backsUpToICloud,
            hidesAmountsInAppSwitcher: hidesAmountsInAppSwitcher,
        )
        do {
            completedSettings = try await completeOnboarding.execute(draft)
            path.append(.done)
        } catch {
            errorMessage = String(localized: "We couldn't save your data. Try again.", bundle: #bundle)
        }
    }

    private func syncCashCurrency() {
        let currency = second ?? principal
        for index in accounts.indices where accounts[index].kind == .cash {
            accounts[index].currency = currency
        }
        for index in accounts.indices where accounts[index].kind == .bank && accounts[index].currency != second {
            accounts[index].currency = principal
        }
    }

    static func fullName(for code: String) -> String {
        let name = Locale.current.localizedString(forCurrencyCode: code) ?? code
        return name.prefix(1).uppercased() + name.dropFirst()
    }

    static func shortName(for code: String) -> String {
        fullName(for: code).split(separator: " ").first.map(String.init) ?? code
    }
}
