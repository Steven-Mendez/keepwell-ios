import SwiftUI

/// A short message that floats above the content with one action ("Notification deleted · Undo"),
/// for taking back something that already happened. Place it at the bottom of a screen and drop it
/// after a few seconds.
public struct KWToast: View {
    private let message: String
    private let actionTitle: String
    private let action: () -> Void

    public init(_ message: String, actionTitle: String, action: @escaping () -> Void) {
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        HStack(spacing: KWSpacing.sm) {
            Text(message)
                .font(KWTextStyle.caption.font.weight(.semibold))
                .foregroundStyle(KWColor.Text.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: action) {
                Text(actionTitle)
                    .font(KWTextStyle.caption.font.weight(.bold))
                    .foregroundStyle(KWColor.Brand.link)
                    .frame(minHeight: KWLayout.minTouch)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, KWSpacing.md)
        .padding(.trailing, KWSpacing.sm)
        .background(KWColor.Surface.surface2, in: RoundedRectangle(cornerRadius: KWRadius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: KWRadius.card, style: .continuous).stroke(KWColor.Surface.border, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
        .accessibilityElement(children: .combine)
    }
}
