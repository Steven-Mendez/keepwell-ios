import Foundation

/// The name the person goes by, as the app greets them and prints it on their own cards.
public enum PreferredName {
    /// Long enough for a first name and a surname, short enough to fit a greeting and a card.
    public static let maxLength = 30

    /// Trimmed and capped; blank means "no name", so nothing ever greets an empty string.
    public static func normalized(_ name: String?) -> String? {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : String(trimmed.prefix(maxLength))
    }
}

/// Reads the name given in onboarding or Settings; one store for the lock, home and the cards.
public protocol GetPreferredNameUseCase: Sendable {
    func execute() async -> String?
}

public struct DefaultGetPreferredNameUseCase: GetPreferredNameUseCase {
    private let profile: any ProfileRepository

    public init(profile: any ProfileRepository) {
        self.profile = profile
    }

    public func execute() async -> String? {
        await PreferredName.normalized(profile.preferredName())
    }
}

/// Saves the name; blank removes it.
public protocol SetPreferredNameUseCase: Sendable {
    func execute(_ name: String) async
}

public struct DefaultSetPreferredNameUseCase: SetPreferredNameUseCase {
    private let profile: any ProfileRepository

    public init(profile: any ProfileRepository) {
        self.profile = profile
    }

    public func execute(_ name: String) async {
        await profile.setPreferredName(PreferredName.normalized(name))
    }
}
