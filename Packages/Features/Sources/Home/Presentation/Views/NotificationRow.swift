import DesignSystem
import SharedPresentation
import SwiftUI

/// One notification: its icon, title (bolder while unread), detail and the unread dot.
struct NotificationRow: View {
    let item: InboxItem
    /// "Hide balances": the title stays, the detail goes when it carries amounts.
    let hidesBalances: Bool

    private func color(_ tone: InboxItem.Tone) -> Color {
        switch tone {
        case .pending: KWColor.State.pending
        case .accent: KWColor.Brand.link
        case .negative: KWColor.State.negative
        }
    }

    var body: some View {
        let tint = color(item.tone)
        let showsChevron = item.destination != nil
        return HStack(spacing: KWSpacing.sm) {
            Group {
                if let category = item.category {
                    CategorySymbol(category, size: 18)
                } else {
                    KWIconView(item.icon, size: 18)
                }
            }
            .foregroundStyle(tint)
            .frame(width: 36, height: 36)
            .background(tint.opacity(0.15), in: Circle())
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.kw(15, weight: item.isRead ? 500 : 700, relativeTo: .subheadline))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                // The warning stays under "hide balances"; only the amounts in its detail go.
                if !(hidesBalances && item.bodyHasAmounts) {
                    Text(item.body)
                        .font(KWTextStyle.caption.font.weight(.regular))
                        .foregroundStyle(KWColor.Text.muted)
                        .multilineTextAlignment(.leading)
                        .monospacedDigit()
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            if !item.isRead {
                Circle()
                    .fill(KWColor.Brand.link)
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
            }
            if showsChevron {
                KWIconView(.chevronRight, size: 16)
                    .foregroundStyle(KWColor.Text.muted)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, KWSpacing.xs)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityValue(item.isRead ? Text("") : Text("Unread", bundle: #bundle))
    }
}
