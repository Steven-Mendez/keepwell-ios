import Foundation

/// The languages the app is translated into.
public enum AppLanguage: String, CaseIterable, Sendable {
    case spanish = "es"
    case english = "en"

    /// The supported language a code like "es-419" or "en-US" belongs to.
    public init?(code: String) {
        guard let language = Locale(identifier: code).language.languageCode?.identifier else { return nil }
        self.init(rawValue: language)
    }

    /// Each language in its own words, so whoever needs it can read it ("Español", "English").
    public var nativeName: String {
        switch self {
        case .spanish: "Español"
        case .english: "English"
        }
    }
}

/// The language chosen for this app. iOS applies an app's language only when the app opens, so a
/// change takes effect the next time Keepwell is opened.
public protocol LanguagePreference: Sendable {
    /// The language the screens are in right now.
    var current: AppLanguage { get }
    /// Whether the person already picked one (onboarding asks once).
    var hasChosen: Bool { get }
    /// Saves the choice. Returns whether Keepwell must be reopened to show it.
    func choose(_ language: AppLanguage) -> Bool
}
