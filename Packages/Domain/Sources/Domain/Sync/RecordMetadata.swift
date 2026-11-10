import Foundation

/// When a stored record was created, last changed and soft-deleted. The store stamps it on every
/// write, so entities stay free of it; the sync engine reads it to merge copies
/// of the same record from different devices (last `updatedAt` wins, a `deletedAt` is a tombstone).
public struct RecordMetadata: Hashable, Sendable {
    public let createdAt: Date
    public let updatedAt: Date
    /// `nil` while the record is alive. Deleted records stay stored so the deletion can reach
    /// other devices instead of the record coming back from one that still has it.
    public let deletedAt: Date?

    public init(createdAt: Date, updatedAt: Date, deletedAt: Date? = nil) {
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    public var isDeleted: Bool {
        deletedAt != nil
    }
}
