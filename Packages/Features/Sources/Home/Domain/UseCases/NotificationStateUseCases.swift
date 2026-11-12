import Domain
import Foundation

public protocol ListNotificationStatesUseCase: Sendable {
    func execute() async throws(DomainError) -> [NotificationState]
}

public struct DefaultListNotificationStatesUseCase: ListNotificationStatesUseCase {
    private let repository: any NotificationStateRepository

    public init(repository: any NotificationStateRepository) {
        self.repository = repository
    }

    public func execute() async throws(DomainError) -> [NotificationState] {
        try await repository.fetchNotificationStates()
    }
}

/// Read, unread, delete and undo delete: one use case with the action as its argument, since each
/// is the same write to the same ids.
public protocol ChangeNotificationsUseCase: Sendable {
    func execute(_ change: NotificationState.Change, ids: [String]) async throws(DomainError)
}

public struct DefaultChangeNotificationsUseCase: ChangeNotificationsUseCase {
    private let repository: any NotificationStateRepository

    public init(repository: any NotificationStateRepository) {
        self.repository = repository
    }

    public func execute(_ change: NotificationState.Change, ids: [String]) async throws(DomainError) {
        guard !ids.isEmpty else { return }
        try await repository.apply(change, to: ids)
    }
}

public protocol PruneNotificationStatesUseCase: Sendable {
    func execute(now: Date) async throws(DomainError)
}

public struct DefaultPruneNotificationStatesUseCase: PruneNotificationStatesUseCase {
    private let repository: any NotificationStateRepository

    public init(repository: any NotificationStateRepository) {
        self.repository = repository
    }

    public func execute(now: Date) async throws(DomainError) {
        try await repository.pruneNotificationStates(now: now)
    }
}
