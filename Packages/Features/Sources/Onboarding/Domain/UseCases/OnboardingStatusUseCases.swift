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

/// Signing in during onboarding: an account whose cloud holds user data (accounts, cards,
/// movements, recurring rules, loans, debts, goals or rules, from the web or another iPhone) brings
/// it down through sync, and the setup steps are skipped. An account with only settings and
/// categories (an account made elsewhere, never used) brings nothing worth skipping setup for, so
/// onboarding goes on and what it saves syncs up. Waits until that data arrives, or until a sync
/// round ends without it.
public protocol RestoreFromAccountUseCase: Sendable {
    /// The settings to go home with, or `nil` when the account has no data to bring.
    func execute() async throws(DomainError) -> Settings?
}

public struct DefaultRestoreFromAccountUseCase: RestoreFromAccountUseCase {
    private let settings: any SettingsRepository
    private let hasUserData: @Sendable () async -> Bool
    private let completedSyncRounds: @Sendable () async -> Int
    private let waitForRoundEnd: @Sendable (Int) async -> Void
    private let timeout: Duration

    /// `hasUserData` reads this device's store, which before onboarding holds only what sync
    /// brought down. `completedSyncRounds` counts the sync rounds that have ended, failed ones
    /// included, and `waitForRoundEnd(n)` suspends until one more has ended after `n` (and
    /// returns early when cancelled); a round that ends after the wait began has pulled whatever
    /// the account had. `timeout` bounds the wait when sync never answers (offline).
    public init(
        settings: any SettingsRepository,
        hasUserData: @escaping @Sendable () async -> Bool,
        completedSyncRounds: @escaping @Sendable () async -> Int,
        waitForRoundEnd: @escaping @Sendable (Int) async -> Void,
        timeout: Duration = .seconds(30),
    ) {
        self.settings = settings
        self.hasUserData = hasUserData
        self.completedSyncRounds = completedSyncRounds
        self.waitForRoundEnd = waitForRoundEnd
        self.timeout = timeout
    }

    public func execute() async throws(DomainError) -> Settings? {
        let roundsBefore = await completedSyncRounds()
        let wait = waitForRoundEnd
        let limit = timeout
        // Whichever comes first: the round ends, or the time runs out.
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await wait(roundsBefore) }
            group.addTask { try? await Task.sleep(for: limit) }
            await group.next()
            group.cancelAll()
        }
        guard await hasUserData() else { return nil }
        return try await completedSettings()
    }

    /// The account's settings, marked as set up: the next launch must open home, even for data
    /// whose settings never said so (or never came).
    private func completedSettings() async throws(DomainError) -> Settings {
        var synced = try await settings.load() ?? Settings(currencies: .initial)
        if !synced.hasCompletedOnboarding {
            synced.hasCompletedOnboarding = true
            try await settings.save(synced)
        }
        return synced
    }
}

/// Asks iOS for permission to show the reminders listed on the privacy step.
public protocol NotificationAuthorizing: Sendable {
    func requestAuthorization() async -> Bool
}
