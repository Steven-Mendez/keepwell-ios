import SwiftUI

/// One tab of the main navigation.
public struct KWTabItem<ID: Hashable>: Identifiable {
    public let id: ID
    public let icon: KWIcon
    public let title: String

    public init(id: ID, icon: KWIcon, title: String) {
        self.id = id
        self.icon = icon
        self.title = title
    }
}

/// Bottom navigation: 84pt including the home-indicator area, `nav` background and a top divider.
public struct KWTabBar<ID: Hashable>: View {
    private let items: [KWTabItem<ID>]
    @Binding private var selection: ID

    public init(items: [KWTabItem<ID>], selection: Binding<ID>) {
        self.items = items
        _selection = selection
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(items) { item in
                let isSelected = item.id == selection
                Button {
                    selection = item.id
                } label: {
                    VStack(spacing: KWSpacing.xxs) {
                        KWIconView(item.icon, size: 24)
                        Text(item.title)
                            .font(KWTextStyle.micro.font)
                            .lineLimit(1)
                    }
                    .foregroundStyle(isSelected ? KWColor.Text.primary : KWColor.Text.faint)
                    .frame(minWidth: 60)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(.top, 10)
        // The design's 84pt includes the 34pt home-indicator area, which the background fills.
        .frame(height: KWLayout.tabBar - 34, alignment: .top)
        .frame(maxWidth: .infinity)
        .background {
            KWColor.Surface.nav
                .overlay(alignment: .top) { KWDivider() }
                .ignoresSafeArea(edges: .bottom)
        }
    }
}

#Preview {
    @Previewable @State var selection = 0
    VStack {
        Spacer()
        KWTabBar(
            items: [
                KWTabItem(id: 0, icon: .home, title: "Inicio"),
                KWTabItem(id: 1, icon: .list, title: "Movimientos"),
                KWTabItem(id: 2, icon: .tabAccounts, title: "Cuentas"),
                KWTabItem(id: 3, icon: .chartBars, title: "Resumen"),
            ],
            selection: $selection,
        )
    }
    .background(KWColor.Surface.bg)
    .onAppear { KWFonts.register() }
}
