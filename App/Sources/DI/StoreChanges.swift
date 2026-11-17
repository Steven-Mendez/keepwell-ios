import Observation
import SwiftUI

/// Counts the changes the store has taken, whoever made them: a screen here, a sync round bringing
/// what another device or an assistant changed, a widget. Screens that show stored data reload when
/// it moves, so a change made elsewhere appears without leaving the screen and coming back.
@MainActor
@Observable
final class StoreChanges {
    private(set) var revision = 0

    func changed() {
        revision += 1
    }
}

private struct ReloadOnStoreChange: ViewModifier {
    @Environment(StoreChanges.self) private var changes
    let container: AppContainer?
    let reload: @MainActor () async -> Void

    func body(content: Content) -> some View {
        if let container {
            reloading(content)
                // Pulling down asks the account for changes now instead of waiting for the next round.
                .refreshable {
                    await container.refreshFromCloud()
                    await reload()
                }
        } else {
            reloading(content)
        }
    }

    private func reloading(_ content: Content) -> some View {
        content.onChange(of: changes.revision) { Task { await reload() } }
    }
}

extension View {
    /// For screens that list or show stored data, never for a form someone is typing in: reloads
    /// when the store changes, and on pull to refresh when `container` is given.
    func reloadsOnStoreChange(refreshingWith container: AppContainer? = nil, _ reload: @escaping @MainActor () async -> Void) -> some View {
        modifier(ReloadOnStoreChange(container: container, reload: reload))
    }
}
