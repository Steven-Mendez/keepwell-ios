import DesignSystem
import SwiftUI

/// The four tabs of the design. Each tab's screen arrives with its feature.
enum MainTab: Hashable {
    case home
    case transactions
    case accounts
    case summary

    static let items = [
        KWTabItem(id: Self.home, icon: .home, title: "Inicio"),
        KWTabItem(id: Self.transactions, icon: .list, title: "Movimientos"),
        KWTabItem(id: Self.accounts, icon: .tabAccounts, title: "Cuentas"),
        KWTabItem(id: Self.summary, icon: .chartBars, title: "Resumen"),
    ]
}

struct MainTabView<Content: View>: View {
    @Binding var selection: MainTab
    @ViewBuilder let content: (MainTab) -> Content

    var body: some View {
        VStack(spacing: 0) {
            content(selection)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            KWTabBar(items: MainTab.items, selection: $selection)
        }
        .background(KWColor.Surface.bg)
    }
}
