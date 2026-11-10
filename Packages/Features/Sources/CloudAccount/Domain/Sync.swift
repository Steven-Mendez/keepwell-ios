import Foundation

/// Where sync stands, for the account section.
public enum SyncState: Equatable, Sendable {
    case idle(lastSync: Date?, pending: Int)
    case syncing
    /// The account lacks `cloud_sync`: local use goes on; nothing is retried until /me changes.
    case needsPlan
    case signedOut
    case offline(pending: Int)
    case failed(requestID: String?)
}

/// An event the server refused, kept so the person can see what stayed only on this iPhone.
public struct RejectedChange: Equatable, Sendable, Codable {
    public let entity: String
    public let entityID: String
    public let reason: String
    public let at: Date

    public init(entity: String, entityID: String, reason: String, at: Date) {
        self.entity = entity
        self.entityID = entityID
        self.reason = reason
        self.at = at
    }
}
