import SwiftUI

/// What a screen shows when it has nothing to list: an icon in a circle, a short title, one
/// sentence and, when there is an obvious next step, a primary action.
public struct KWEmptyState: View {
    private let icon: KWIcon
    private let title: String
    private let message: String
    private let actionTitle: String?
    private let action: (() -> Void)?

    public init(icon: KWIcon, title: String, message: String, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.icon = icon
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        VStack(spacing: KWSpacing.md) {
            KWIconView(icon, size: 28)
                .foregroundStyle(KWColor.Text.secondary)
                .frame(width: 64, height: 64)
                .background(KWColor.Surface.surface, in: Circle())
                .padding(.bottom, KWSpacing.xxs)
            VStack(spacing: KWSpacing.xs) {
                Text(title)
                    .font(.kw(20, weight: 800, relativeTo: .title3))
                    .foregroundStyle(KWColor.Text.primary)
                    .accessibilityAddTraits(.isHeader)
                Text(message)
                    .font(KWTextStyle.body.font)
                    .foregroundStyle(KWColor.Text.muted)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.center)
            // Only the text is inset, for shorter lines; the action spans the screen's gutter
            // like every other full-width button, so its edges meet the header and cards above.
            .padding(.horizontal, KWSpacing.md)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.kw())
                    .padding(.top, KWSpacing.xs)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    KWEmptyState(
        icon: .list,
        title: "No transactions yet",
        message: "Log your first expense, income or transfer and it shows up here.",
        actionTitle: "Log transaction",
    ) {}
        .padding(KWLayout.gutter)
        .background(KWColor.Surface.bg)
        .onAppear { KWFonts.register() }
}
