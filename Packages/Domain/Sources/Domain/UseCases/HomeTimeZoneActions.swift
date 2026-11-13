import Foundation

/// Sets the home time zone from this device when the settings have none (keepwell-web
/// `fillMissingTimeZone`). Run after a sync, so a zone another device set arrives first and wins.
public protocol FillHomeTimeZoneUseCase: Sendable {
    /// Whether it wrote, so the caller can send the change right away.
    @discardableResult
    func execute() async throws(DomainError) -> Bool
}

public struct DefaultFillHomeTimeZoneUseCase: FillHomeTimeZoneUseCase {
    private let settings: any SettingsRepository
    private let deviceTimeZone: @Sendable () -> String

    public init(settings: any SettingsRepository, deviceTimeZone: @escaping @Sendable () -> String = { TimeZone.current.identifier }) {
        self.settings = settings
        self.deviceTimeZone = deviceTimeZone
    }

    public func execute() async throws(DomainError) -> Bool {
        guard let filled = try await settings.load()?.fillingMissingTimeZone(deviceTimeZone()) else { return false }
        try await settings.save(filled)
        return true
    }
}
