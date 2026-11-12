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

    /// The second currency as the principal, with the rate turned around ("1 USD = 36.6243 NIO"
    /// becomes "1 NIO = 0.0273… USD"). Past transactions keep the rate they stored, which names both
    /// currencies, so their conversions stay right. `nil` with a single currency.
    public func swapped() -> Self? {
        // Twelve decimals: swapping back lands on the original rate to well past what anyone types.
        guard let second, let swapped = try? Self(principal: second, second: principal, rate: (1 / rate).rounded(scale: 12)) else {
            return nil
        }
        return swapped
    }

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
    /// The person's home time zone (IANA identifier): the one Keepwell's server reads "today", month
    /// ends and recurring occurrences in. Set once from the device when missing and changed by hand
    /// in Settings, never on its own, so two devices in different zones don't keep flipping it. The
    /// app's own screens still use the device's calendar. Synced as `time_zone`.
    public var timeZone: String?

    public init(
        currencies: CurrencySettings,
        unlockMethod: UnlockMethod = .biometrics,
        relockAfter: TimeInterval = 60,
        hidesAmountsInAppSwitcher: Bool = true,
        isICloudBackupEnabled: Bool = true,
        paymentReminderDaysBefore: Int = 3,
        hasCompletedOnboarding: Bool = false,
        timeZone: String? = nil,
    ) {
        self.currencies = currencies
        self.unlockMethod = unlockMethod
        self.relockAfter = relockAfter
        self.hidesAmountsInAppSwitcher = hidesAmountsInAppSwitcher
        self.isICloudBackupEnabled = isICloudBackupEnabled
        self.paymentReminderDaysBefore = paymentReminderDaysBefore
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.timeZone = timeZone
    }

    /// These settings with `zone` as the home time zone when they have none yet, after onboarding;
    /// `nil` when nothing should change. A zone set on another device always wins over this one.
    public func fillingMissingTimeZone(_ zone: String) -> Self? {
        guard hasCompletedOnboarding, timeZone == nil, HomeTimeZone.isWellFormed(zone) else { return nil }
        var filled = self
        filled.timeZone = zone
        return filled
    }
}

/// The rules every platform shares for the home zone (keepwell-web `TimeZoneId`).
public enum HomeTimeZone {
    /// An IANA name's shape ("America/Managua", "Etc/GMT+6", "UTC"). Only the shape: the zone
    /// databases of iOS, browsers and the server differ by version, and a name one of them doesn't
    /// know must not get the settings row rejected.
    public static func isWellFormed(_ identifier: String) -> Bool {
        identifier.count <= 64 && identifier.wholeMatch(of: /[A-Za-z][A-Za-z0-9_+\-]*(\/[A-Za-z0-9_+\-]+)*/) != nil
    }

    /// The calendar a home zone reads days in: the Gregorian calendar in that zone, or `nil` when
    /// this iPhone doesn't know the zone.
    public static func calendar(_ identifier: String) -> Calendar? {
        guard let zone = TimeZone(identifier: identifier) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar
    }
}
