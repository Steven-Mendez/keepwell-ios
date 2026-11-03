import DesignSystem
import SwiftUI

/// Stands in for tabs whose screen hasn't been built yet, so they never show a blank screen.
/// Without movements it shows the real empty state and offers to log one; with movements it
/// says the screen is on its way instead of claiming there's no data.
struct PendingTabView: View {
    let tab: MainTab
    let hasMovements: Bool
    let onNewMovement: () -> Void

    var body: some View {
        KWScreen(bottom: KWSpacing.md) {
            VStack(spacing: 0) {
                KWLargeTitleHeader(title) {
                    if tab == .transactions {
                        KWCircleButton(.plus, style: .white, accessibilityLabel: "Nuevo movimiento", action: onNewMovement)
                    }
                }
                Spacer(minLength: KWSpacing.md)
                if hasMovements {
                    KWEmptyState(
                        icon: icon,
                        title: "Pantalla en camino",
                        message: "Esta sección todavía se está construyendo. Tus movimientos ya están guardados.",
                    )
                } else {
                    KWEmptyState(
                        icon: icon,
                        title: emptyTitle,
                        message: emptyMessage,
                        actionTitle: "Anotar movimiento",
                        action: onNewMovement,
                    )
                }
                Spacer(minLength: KWSpacing.md)
            }
        }
    }

    private var title: String {
        switch tab {
        case .home: "Inicio"
        case .transactions: "Movimientos"
        case .accounts: "Cuentas"
        case .summary: "Resumen"
        }
    }

    private var icon: KWIcon {
        switch tab {
        case .home: .home
        case .transactions: .list
        case .accounts: .tabAccounts
        case .summary: .chartBars
        }
    }

    private var emptyTitle: String {
        tab == .summary ? "Tu resumen empieza con un movimiento" : "Aún no tienes movimientos"
    }

    private var emptyMessage: String {
        switch tab {
        case .summary: "Cuando anotes gastos e ingresos verás cuánto entró, cuánto salió y en qué gastaste."
        case .home: "Anota tu primer gasto, ingreso o transferencia y aquí verás tu mes."
        case .transactions, .accounts: "Anota tu primer gasto, ingreso o transferencia y aparece aquí."
        }
    }
}
