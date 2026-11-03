import Domain
import Foundation

/// Keeps the app's language in `UserDefaults`: `AppleLanguages` in the app's own domain is the
/// per-app language iOS reads when the app launches (the same one Settings › Keepwell › Language
/// writes), so a choice made in the app sticks without touching the rest of the iPhone.
public struct LanguageStore: LanguagePreference, @unchecked Sendable {
    // `UserDefaults` is documented as thread-safe; it just isn't marked `Sendable`.
    private let defaults: UserDefaults
    private let bundle: Bundle
    private static let chosenKey = "language.chosen"
    private static let languagesKey = "AppleLanguages"

    public init(defaults: UserDefaults = .standard, bundle: Bundle = .main) {
        self.defaults = defaults
        self.bundle = bundle
    }

    /// The localization this launch is actually using, which is what the screens show.
    public var current: AppLanguage {
        bundle.preferredLocalizations.lazy.compactMap(AppLanguage.init(code:)).first ?? .english
    }

    public var hasChosen: Bool {
        defaults.bool(forKey: Self.chosenKey)
    }

    public func choose(_ language: AppLanguage) -> Bool {
        defaults.set(true, forKey: Self.chosenKey)
        defaults.set([language.rawValue], forKey: Self.languagesKey)
        return language != current
    }
}
