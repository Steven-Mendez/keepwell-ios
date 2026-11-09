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
        /// "Have you used Keepwell before?": restore a backup or start from scratch.
        case returning
        case name
        case currencies
        case accounts
        case protect
        case privacy
        case done
    }

    public enum RestoreState: Equatable, Sendable {
        case idle
        case searching
        case notFound
    }

    /// One currency, or a main one plus a second with a rate between them.
    public enum CurrencyMode: Hashable, Sendable {
        case single
        case dual
    }

    /// Pushed steps after the welcome screen.
    public var path: [Step] = []
    /// What to call the person; saved with everything else at the end.
    public var nameText = ""
    public private(set) var currencyMode = CurrencyMode.single
    public private(set) var principal: String
    /// Kept while the person is on one currency, so going back to two restores their pick.
    public private(set) var secondChoice: String
    public var rateText = OnboardingViewModel.defaultRateText
    public private(set) var accounts: [OnboardingAccountDraft]
    public var locksWithBiometrics = true
    /// A Keepwell passcode was created on the protect step.
    public private(set) var hasPasscode = false
    public var hidesAmountsInAppSwitcher = true
    public private(set) var restoreState = RestoreState.idle
    public private(set) var isSaving = false
    public private(set) var errorMessage: String?
    public private(set) var completedSettings: Settings?
    private var searchedCurrencies: [String] = []

    private let completeOnboarding: any CompleteOnboardingUseCase
    private let restoreFromBackup: any RestoreFromBackupUseCase
    private let notifications: any NotificationAuthorizing

    static let defaultRateText = "1.0000"
    /// The most used currencies, offered before "Search…" so most people pick with one tap.
    static let commonCurrencies = ["USD", "EUR", "GBP", "MXN", "CAD", "JPY", "CHF", "BRL"]

    public init(
        completeOnboarding: any CompleteOnboardingUseCase,
        restoreFromBackup: any RestoreFromBackupUseCase,
        notifications: any NotificationAuthorizing,
        regionCurrency: String? = Locale.current.currency?.identifier,
    ) {
        self.completeOnboarding = completeOnboarding
        self.restoreFromBackup = restoreFromBackup
        self.notifications = notifications
        // The region's currency is the likeliest main one; anything unknown falls back to USD.
        let principal = regionCurrency.flatMap { code in
            Locale.commonISOCurrencyCodes.contains(code) ? code : nil
        } ?? "USD"
        self.principal = principal
        secondChoice = Self.commonCurrencies.first { $0 != principal } ?? "EUR"
        accounts = [OnboardingAccountDraft(kind: .cash, name: String(localized: "Cash", bundle: #bundle), currency: principal)]
    }

    // MARK: Currencies

    /// The second currency, or `nil` on one currency.
    public var second: String? {
        currencyMode == .dual ? secondChoice : nil
    }

    /// Quick picks for the second currency: the common ones, then anything found with "Search…".
    public var secondCurrencyOptions: [String] {
        (Self.commonCurrencies + searchedCurrencies + [secondChoice])
            .reduce(into: [String]()) { codes, code in
                if code != principal, !codes.contains(code) {
                    codes.append(code)
                }
            }
    }

    /// The main currency's quick picks: the current one first, then the common ones.
    public var principalOptions: [String] {
        [principal] + Self.commonCurrencies.filter { $0 != principal }
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

    public func setCurrencyMode(_ mode: CurrencyMode) {
        currencyMode = mode
        syncAccountCurrencies()
    }

    /// Picking the current second currency as the main one swaps them, so the two never match
    /// and the second isn't silently dropped.
    public func selectPrincipal(_ code: String) {
        guard code != principal else { return }
        guard code != secondChoice else {
            swapCurrencies()
            return
        }
        principal = code
        rateText = Self.defaultRateText
        syncAccountCurrencies()
    }

    /// Choosing a currency resets the rate to 1, as the design does: the old rate belonged to
    /// another currency.
    public func selectSecond(_ code: String) {
        guard code != principal else { return }
        if !Self.commonCurrencies.contains(code), !searchedCurrencies.contains(code) {
            searchedCurrencies.append(code)
        }
        if code != secondChoice {
            secondChoice = code
            rateText = Self.defaultRateText
        }
        syncAccountCurrencies()
    }

    /// The rate keeps describing the same exchange, so it's inverted: 1 USD = 36.6243 NIO
    /// becomes 1 NIO = 0.027304 USD.
    public func swapCurrencies() {
        (principal, secondChoice) = (secondChoice, principal)
        if let rate, rate != 1 {
            rateText = Self.rateText(for: 1 / rate)
        }
        syncAccountCurrencies()
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
        case .cash:
            // One cash account per currency: a new one takes the first currency without one, and
            // once every currency has its cash the tile opens the existing one instead.
            if let currency = freeCashCurrencies(excluding: nil).first {
                OnboardingAccountDraft(kind: .cash, name: String(localized: "Cash", bundle: #bundle), currency: currency)
            } else {
                accounts.first { $0.kind == .cash } ?? OnboardingAccountDraft(
                    kind: .cash,
                    name: String(localized: "Cash", bundle: #bundle),
                    currency: principal,
                )
            }
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
        accounts.removeAll { $0.id == id }
    }

    // MARK: Navigation

    /// "Start" on the welcome: asks whether there's a backup to bring before setting anything up.
    public func begin() {
        path = [.returning]
    }

    /// "Start from scratch": the setup steps, with the question still one step back.
    public func start() {
        path = [.returning, .name]
    }

    /// The trimmed name, or `nil` while the field is blank.
    public var preferredName: String? {
        PreferredName.normalized(nameText)
    }

    public func continueFromName() {
        nameText = String(nameText.prefix(PreferredName.maxLength))
        path.append(.currencies)
    }

    /// "Skip": the greeting and the cards simply go without a name.
    public func skipName() {
        nameText = ""
        path.append(.currencies)
    }

    public func continueFromCurrencies() {
        guard canContinueFromCurrencies else { return }
        path.append(.accounts)
    }

    public func continueFromAccounts() {
        path.append(.protect)
    }

    /// The passcode setup screen saved a code; it's already in the Keychain.
    public func passcodeCreated() {
        hasPasscode = true
    }

    public func continueFromProtect() {
        path.append(.privacy)
    }

    /// "Not now": no Keepwell passcode. Face ID, if left on, still locks the app with the
    /// iPhone passcode behind it.
    public func skipPasscode() {
        hasPasscode = false
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

    /// "All set, Steven" once there's a name to say.
    public var doneTitle: String {
        guard let name = preferredName else { return String(localized: "All set", bundle: #bundle) }
        return String(localized: "All set, \(name)", bundle: #bundle)
    }

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
            accounts: accountsToSave,
            locksWithBiometrics: locksWithBiometrics,
            hidesAmountsInAppSwitcher: hidesAmountsInAppSwitcher,
            preferredName: preferredName,
            hasPasscode: hasPasscode,
        )
        do {
            completedSettings = try await completeOnboarding.execute(draft)
            path.append(.done)
        } catch {
            errorMessage = String(localized: "We couldn't save your data. Try again.", bundle: #bundle)
        }
    }

    /// Cash and bank accounts keep the currency they were given while it's still one of the
    /// chosen ones; a dropped currency falls back to the main one. Cash in a dropped currency goes
    /// when the main one already has cash, since there's one cash account per currency.
    private func syncAccountCurrencies() {
        let chosen = currencies
        let principalHasCash = accounts.contains { $0.kind == .cash && $0.currency == principal }
        accounts.removeAll { $0.kind == .cash && !chosen.contains($0.currency) && principalHasCash }
        for index in accounts.indices where accounts[index].kind != .credit && !chosen.contains(accounts[index].currency) {
            accounts[index].currency = principal
        }
    }

    static func fullName(for code: String) -> String {
        let name = Locale.current.localizedString(forCurrencyCode: code) ?? code
        return name.prefix(1).uppercased() + name.dropFirst()
    }

    /// Six decimals keep an inverted rate like 1 / 36.6243 meaningful; trailing zeros go.
    static func rateText(for rate: Decimal) -> String {
        var value = rate
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, 6, .plain)
        return "\(rounded)"
    }
}
