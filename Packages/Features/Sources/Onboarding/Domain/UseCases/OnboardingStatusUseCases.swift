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

/// Signing in during onboarding: an account that already holds Keepwell data (from the web or
/// another iPhone) brings it down through sync, and the setup steps are skipped. Waits until
/// finished settings arrive, or until a sync round ends without them (a new or empty account).
public protocol RestoreFromAccountUseCase: Sendable {
    /// The synced settings, or `nil` when the account has none to bring.
    func execute() async throws(DomainError) -> Settings?
}

public struct DefaultRestoreFromAccountUseCase: RestoreFromAccountUseCase {
    private let settings: any SettingsRepository
    private let completedSyncRounds: @Sendable () async -> Int
    private let attempts: Int
    private let interval: Duration

    /// `completedSyncRounds` counts the sync rounds that have ended, failed ones included; a round
    /// that ends after the wait began has pulled whatever the account had. `attempts` bounds the
    /// wait when sync never answers (offline).
    public init(
        settings: any SettingsRepository,
        completedSyncRounds: @escaping @Sendable () async -> Int,
        attempts: Int = 60,
        interval: Duration = .milliseconds(500),
    ) {
        self.settings = settings
        self.completedSyncRounds = completedSyncRounds
        self.attempts = attempts
        self.interval = interval
    }

    public func execute() async throws(DomainError) -> Settings? {
        let roundsBefore = await completedSyncRounds()
        for attempt in 0 ..< attempts {
            let roundEnded = await completedSyncRounds() > roundsBefore
            if let synced = try await settings.load(), synced.hasCompletedOnboarding {
                return synced
            }
            if roundEnded {
                return nil
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
