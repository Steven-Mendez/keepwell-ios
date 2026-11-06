import Foundation

/// Principal currency (reports and net worth), optional second currency and the manual rate.
public struct CurrencySettings: Hashable, Sendable, Codable {
    public let principal: String
    /// `nil` in single-currency mode.
    public let second: String?
    /// "1 principal = rate second". Defaults to 1 until the person replaces it.
    public let rate: Decimal

    public init(principal: String = "USD", second: String? = nil, rate: Decimal = 1) throws(DomainError) {
        guard rate > 0 else { throw .invalidExchangeRate }
        self.principal = principal
        self.second = second == principal ? nil : second
        self.rate = self.second == nil ? 1 : rate
    }

    /// USD alone at rate 1: what screens assume before onboarding has saved real settings.
    public static let initial: CurrencySettings = {
        guard let settings = try? Self() else { preconditionFailure("The default currency settings are valid") }
        return settings
    }()

    /// The rate new transactions store.
    public var exchangeRate: ExchangeRate {
        guard let second, let rate = try? ExchangeRate(principal: principal, second: second, rate: rate) else {
            return .single(principal)
        }
        return rate
    }
}

public enum UnlockMethod: String, Codable, CaseIterable, Sendable {
    /// Face ID or Touch ID, whichever the device has, falling back to the passcode.
    case biometrics
    case passcode
    case disabled
}

public struct Settings: Hashable, Sendable, Codable {
    public var currencies: CurrencySettings
    public var unlockMethod: UnlockMethod
    /// Seconds in the background before the lock is asked again.
    public var relockAfter: TimeInterval
    public var hidesAmountsInAppSwitcher: Bool
    public var isICloudBackupEnabled: Bool
    public var paymentReminderDaysBefore: Int
    public var hasCompletedOnboarding: Bool

    public init(
        currencies: CurrencySettings,
        unlockMethod: UnlockMethod = .biometrics,
        relockAfter: TimeInterval = 60,
        hidesAmountsInAppSwitcher: Bool = true,
        isICloudBackupEnabled: Bool = true,
        paymentReminderDaysBefore: Int = 3,
        hasCompletedOnboarding: Bool = false,
    ) {
        self.currencies = currencies
        self.unlockMethod = unlockMethod
        self.relockAfter = relockAfter
        self.hidesAmountsInAppSwitcher = hidesAmountsInAppSwitcher
        self.isICloudBackupEnabled = isICloudBackupEnabled
        self.paymentReminderDaysBefore = paymentReminderDaysBefore
        self.hasCompletedOnboarding = hasCompletedOnboarding
    }
}
