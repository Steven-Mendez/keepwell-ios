import Domain
import Foundation

public protocol GetSettingsUseCase: Sendable {
    /// `nil` until onboarding finishes on this or another device.
    func execute() async throws(DomainError) -> Settings?
}

public struct DefaultGetSettingsUseCase: GetSettingsUseCase {
    private let repository: any SettingsRepository

    public init(repository: any SettingsRepository) {
        self.repository = repository
    }

    public func execute() async throws(DomainError) -> Settings? {
        try await repository.load()
    }
}

/// "I've used it before: restore from my Keepwell account". Once the person signs in, sync brings
/// the data down on its own; this waits for finished settings to arrive.
public protocol RestoreFromBackupUseCase: Sendable {
    /// The restored settings, or `nil` when nothing arrived within the wait.
    func execute() async throws(DomainError) -> Settings?
}

public struct DefaultRestoreFromBackupUseCase: RestoreFromBackupUseCase {
    private let settings: any SettingsRepository
    private let attempts: Int
    private let interval: Duration

    public init(
        settings: any SettingsRepository,
        attempts: Int = 30,
        interval: Duration = .seconds(1),
    ) {
        self.settings = settings
        self.attempts = attempts
        self.interval = interval
    }

    public func execute() async throws(DomainError) -> Settings? {
        for attempt in 0 ..< attempts {
            if let restored = try await settings.load(), restored.hasCompletedOnboarding {
                return restored
            }
            if attempt < attempts - 1 {
                try? await Task.sleep(for: interval)
            }
        }
        return nil
    }
}

/// Asks iOS for permission to show the reminders listed on the privacy step.
public protocol NotificationAuthorizing: Sendable {
    func requestAuthorization() async -> Bool
}
