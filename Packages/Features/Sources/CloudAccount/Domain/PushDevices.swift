import Foundation

/// This iPhone as the server's push job knows it (ADR 0012 in keepwell-api): where to send its
/// notifications, and in which time zone and language to word and time them.
public struct PushDevice: Equatable, Sendable {
    public enum Environment: String, Sendable {
        /// A build signed for development: Xcode and TestFlight-less debug runs.
        case sandbox
        case production
    }

    /// The APNs device token as lowercase hex.
    public let token: String
    /// IANA name ("America/Managua"): the reminder hour is local to it.
    public let timeZone: String
    /// BCP 47 ("es-NI").
    public let locale: String
    public let environment: Environment

    public init(token: String, timeZone: String, locale: String, environment: Environment) {
        self.token = token
        self.timeZone = timeZone
        self.locale = locale
        self.environment = environment
    }

    /// The token as the server stores it.
    public static func hex(_ token: Data) -> String {
        token.map { String(format: "%02x", $0) }.joined()
    }
}

public protocol PushDeviceRepository: Sendable {
    /// Registers this iPhone, or refreshes its token, time zone and language.
    func register(_ device: PushDevice) async throws(CloudAccountError)
    /// Forgets this iPhone: signing out, or deleting the account, must stop its notifications.
    func unregister() async throws(CloudAccountError)
}

public protocol RegisterPushDeviceUseCase: Sendable {
    func execute(_ device: PushDevice) async throws(CloudAccountError)
}

public struct DefaultRegisterPushDeviceUseCase: RegisterPushDeviceUseCase {
    private let repository: any PushDeviceRepository

    public init(repository: any PushDeviceRepository) {
        self.repository = repository
    }

    public func execute(_ device: PushDevice) async throws(CloudAccountError) {
        try await repository.register(device)
    }
}

public protocol UnregisterPushDeviceUseCase: Sendable {
    func execute() async throws(CloudAccountError)
}

public struct DefaultUnregisterPushDeviceUseCase: UnregisterPushDeviceUseCase {
    private let repository: any PushDeviceRepository

    public init(repository: any PushDeviceRepository) {
        self.repository = repository
    }

    public func execute() async throws(CloudAccountError) {
        try await repository.unregister()
    }
}
