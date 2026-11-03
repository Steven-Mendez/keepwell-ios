import Domain
import Foundation

/// How settings values read on screen.
extension SettingsViewModel {
    var rateFootnote: String {
        String(
            // swiftlint:disable:next line_length
            localized: "Update it whenever you like by replacing the value. Each transaction keeps the rate it was logged with, so your history doesn't change.",
            bundle: #bundle,
        )
    }

    /// The language the app is showing, named in that language ("Español").
    var languageName: String {
        let code = Bundle.main.preferredLocalizations.first ?? "en"
        let locale = Locale(identifier: code)
        let name = locale.localizedString(forLanguageCode: code) ?? code
        return name.capitalized(with: locale)
    }

    /// "USD · US dollar", in the person's language.
    func currencyName(_ code: String) -> String {
        guard let name = Locale.current.localizedString(forCurrencyCode: code) else { return code }
        return "\(code) · \(name.prefix(1).uppercased())\(name.dropFirst())"
    }

    func relockTitle(_ seconds: TimeInterval) -> String {
        if seconds <= 0 {
            return String(localized: "Immediately", bundle: #bundle)
        }
        return Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes], width: .wide))
    }

    func reminderTitle(_ days: Int) -> String {
        String(localized: "\(days) days", bundle: #bundle)
    }

    func unlockTitle(_ method: UnlockMethod) -> String {
        switch method {
        case .biometrics: String(localized: "Face ID /\nTouch ID", bundle: #bundle)
        case .passcode: String(localized: "Passcode\nonly", bundle: #bundle)
        case .disabled: String(localized: "No lock", bundle: #bundle)
        }
    }
}
