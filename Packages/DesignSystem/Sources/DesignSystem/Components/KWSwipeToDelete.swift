import SwiftUI

extension View {
    /// Swiping the row left reveals a red delete button, as in Mail and Wallet; a long swipe
    /// deletes straight away. Rows inside custom cards can't use `swipeActions`, which only works
    /// in a `List`. VoiceOver gets the same action from the rotor.
    public func kwSwipeToDelete(isEnabled: Bool = true, onDelete: @escaping () -> Void) -> some View {
        modifier(KWSwipeAction(
            icon: .trash,
            tint: KWColor.State.negative,
            label: Text("Delete", bundle: #bundle),
            isEnabled: isEnabled,
            onAction: onDelete,
        ))
    }

    /// The same swipe with another action, such as confirming a draft: a long swipe acts at once.
    /// `label` names it for VoiceOver.
    public func kwSwipeAction(
        _ icon: KWIcon,
        tint: Color,
        label: Text,
        isEnabled: Bool = true,
        action: @escaping () -> Void,
    ) -> some View {
        modifier(KWSwipeAction(icon: icon, tint: tint, label: label, isEnabled: isEnabled, onAction: action))
    }
}

struct KWSwipeAction: ViewModifier {
    let icon: KWIcon
    let tint: Color
    let label: Text
    let isEnabled: Bool
    let onAction: () -> Void
    @State private var offset: CGFloat = 0
    @State private var isOpen = false
    @State private var isPastFullSwipe = false
    @State private var width: CGFloat = 0

    private let buttonWidth: CGFloat = 80
    private let fullSwipeShare: CGFloat = 0.6

    func body(content: Content) -> some View {
        if isEnabled {
            row(content)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
                .accessibilityAction(named: label, onAction)
        } else {
            content
        }
    }

    private func row(_ content: Content) -> some View {
        content
            .background(KWColor.Surface.surface)
            .offset(x: offset)
            // Taps while open close the row instead of opening it.
            .allowsHitTesting(!isOpen)
            .overlay {
                if isOpen {
                    // Leaves the revealed button uncovered so it still takes its tap.
                    Color.clear
                        .contentShape(Rectangle())
                        .padding(.trailing, buttonWidth)
                        .onTapGesture { close() }
                }
            }
            .background(alignment: .trailing) {
                Button { act() } label: {
                    KWIconView(icon, size: 20)
                        .foregroundStyle(KWColor.Text.onPositive)
                        .frame(width: max(buttonWidth, -offset))
                        .frame(maxHeight: .infinity)
                        .background(tint)
                }
                .buttonStyle(.plain)
                .accessibilityHidden(true)
                .opacity(offset < 0 ? 1 : 0)
            }
            .clipped()
            .simultaneousGesture(drag(width: width))
            .sensoryFeedback(.impact(weight: .medium), trigger: isPastFullSwipe) { _, new in new }
    }

    private func drag(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 16)
            .onChanged { value in
                // Mostly vertical drags belong to whatever scrolls around the row.
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                let start = isOpen ? -buttonWidth : 0
                offset = min(0, start + value.translation.width)
                isPastFullSwipe = -offset > width * fullSwipeShare
            }
            .onEnded { value in
                let start = isOpen ? -buttonWidth : 0
                let end = start + value.predictedEndTranslation.width
                if -offset > width * fullSwipeShare {
                    act()
                } else if end < -buttonWidth / 2 {
                    withAnimation(.snappy) {
                        offset = -buttonWidth
                        isOpen = true
                    }
                } else {
                    close()
                }
                isPastFullSwipe = false
            }
    }

    private func close() {
        withAnimation(.snappy) {
            offset = 0
            isOpen = false
        }
    }

    private func act() {
        withAnimation(.snappy) {
            offset = 0
            isOpen = false
        }
        onAction()
    }
}
