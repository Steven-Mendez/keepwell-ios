import DesignSystem
import SharedPresentation
import SwiftUI

extension RootView {
    // MARK: - Undo

    /// "Transaction deleted · Undo" over every screen, above the tab bar on the tabs. It goes when
    /// the deletion it offers to take back is written.
    @ViewBuilder
    func movementUndoToast(onTabs: Bool) -> some View {
        if let offer = container.movementUndo.offer {
            KWToast(offer.message, actionTitle: MovementUndo.actionTitle) {
                Task { await container.movementUndo.undo(offer) }
            }
            .padding(.horizontal, KWLayout.gutter)
            .padding(.bottom, onTabs ? KWLayout.tabBar - 34 + KWSpacing.md : KWSpacing.md)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .task(id: offer.id) {
                try? await Task.sleep(for: .seconds(MovementUndo.window))
                guard !Task.isCancelled else { return }
                withAnimation { container.movementUndo.dismiss(offer) }
            }
        }
    }
}
