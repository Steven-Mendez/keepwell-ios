import SwiftUI

/// 48pt circular quick action with its caption underneath ("Expense", "Pay", "Freeze").
public struct KWActionButton: View {
    public enum Style: Sendable {
        /// `surface2` circle.
        case neutral
        /// White circle, black icon: the main action.
        case prominent
        /// Translucent white circle on gradients.
        case translucent
        /// Link-colored circle with a black icon: an action currently on ("Unfreeze").
        case active
    }

    private let icon: KWIcon
    private let title: String
    private let style: Style
    private let captionSize: CGFloat
    private let action: () -> Void

    public init(_ title: String, icon: KWIcon, style: Style = .neutral, captionSize: CGFloat = 12, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.style = style
        self.captionSize = captionSize
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            VStack(spacing: KWSpacing.xs) {
                KWIconView(icon, size: 22)
                    .foregroundStyle(iconColor)
                    .frame(width: KWComponentMetrics.actionCircle, height: KWComponentMetrics.actionCircle)
                    .background(background, in: Circle())
                Text(title)
                    .font(.kw(captionSize, weight: 500, relativeTo: .caption))
                    .foregroundStyle(KWColor.Text.primary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var background: Color {
        switch style {
        case .neutral: KWColor.Surface.surface2
        case .prominent: .white
        case .translucent: KWColor.Overlay.white18
        case .active: KWColor.Brand.link
        }
    }

    private var iconColor: Color {
        switch style {
        case .prominent, .active: .black
        case .neutral, .translucent: KWColor.Text.primary
        }
    }
}

#Preview {
    HStack {
        KWActionButton("Pay", icon: .arrowUp, style: .prominent) {}
        KWActionButton("Edit name", icon: .pencil) {}
        KWActionButton("Unfreeze", icon: .freeze, style: .active) {}
        KWActionButton("More", icon: .more) {}
    }
    .padding(KWLayout.gutter)
    .background(KWColor.Surface.bg)
    .onAppear { KWFonts.register() }
}
