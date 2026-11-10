import SwiftUI

/// "Slide to save": a pill whose thumb must be dragged to the end before the action runs, for
/// steps that commit money, where a stray tap shouldn't. Crossing the end gives a firm haptic and
/// turns the thumb into a check; letting go early springs it back.
///
/// VoiceOver can't drag, so the control is a single button there: a double tap confirms. A plain
/// tap nudges the thumb to show it moves.
public struct KWSwipeToConfirm: View {
    private let title: String
    private let accessibilityLabel: String
    private let onConfirm: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var offset: CGFloat = 0
    @State private var isConfirmed = false
    @State private var isPastEnd = false

    private static let height: CGFloat = 60
    private static let inset: CGFloat = 5
    /// Share of the track the thumb must cover; a little short of the end so it doesn't take
    /// pixel precision.
    private static let threshold: CGFloat = 0.85

    /// `accessibilityLabel` is what VoiceOver reads instead of the "slide" instruction ("Save
    /// expense").
    public init(_ title: String, accessibilityLabel: String? = nil, onConfirm: @escaping () -> Void) {
        self.title = title
        self.accessibilityLabel = accessibilityLabel ?? title
        self.onConfirm = onConfirm
    }

    public var body: some View {
        GeometryReader { proxy in
            let thumb = Self.height - 2 * Self.inset
            let travel = max(proxy.size.width - thumb - 2 * Self.inset, 1)
            let progress = min(max(offset / travel, 0), 1)
            ZStack(alignment: .leading) {
                Capsule().fill(KWColor.Surface.surface)
                // The trail fades in with the drag, so the resting control shows no stray ring.
                Capsule()
                    .fill(KWColor.State.positive.opacity(0.22))
                    .frame(width: offset + thumb + 2 * Self.inset)
                    .opacity(isConfirmed ? 1 : min(progress * 4, 1))
                Text(title)
                    .font(KWTextStyle.heading.font)
                    .foregroundStyle(KWColor.Text.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.leading, thumb + KWSpacing.md)
                    .padding(.trailing, KWSpacing.md)
                    .frame(maxWidth: .infinity)
                    .opacity(isConfirmed ? 0 : 1 - progress * 0.9)
                thumbView(size: thumb)
                    .offset(x: Self.inset + offset)
                    .gesture(drag(travel: travel))
            }
            .onTapGesture { nudge(travel: travel) }
        }
        .frame(height: Self.height)
        .modifier(DisabledDimmingModifier())
        .sensoryFeedback(.selection, trigger: isPastEnd) { _, new in new }
        .sensoryFeedback(.success, trigger: isConfirmed) { _, new in new }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(Text("Double tap to confirm.", bundle: #bundle))
        .accessibilityAction { confirm(travel: nil) }
    }

    private func thumbView(size: CGFloat) -> some View {
        KWIconView(isConfirmed ? .check : .arrowRight, size: 22, lineWidth: 2.4)
            .foregroundStyle(isConfirmed ? KWColor.Text.onPositive : KWColor.Semantic.primaryForeground)
            .frame(width: size, height: size)
            .background(isConfirmed ? KWColor.State.positive : KWColor.Semantic.primary, in: Circle())
            .contentShape(Circle())
    }

    private func drag(travel: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard isEnabled, !isConfirmed else { return }
                offset = min(max(value.translation.width, 0), travel)
                isPastEnd = offset >= travel * Self.threshold
            }
            .onEnded { _ in
                guard isEnabled, !isConfirmed else { return }
                if offset >= travel * Self.threshold {
                    confirm(travel: travel)
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { offset = 0 }
                    isPastEnd = false
                }
            }
    }

    private func confirm(travel: CGFloat?) {
        guard isEnabled, !isConfirmed else { return }
        withAnimation(reduceMotion ? nil : .snappy) {
            if let travel {
                offset = travel
            }
            isConfirmed = true
        }
        onConfirm()
    }

    private func nudge(travel: CGFloat) {
        guard isEnabled, !isConfirmed, !reduceMotion else { return }
        withAnimation(.spring(response: 0.25, dampingFraction: 0.5)) { offset = min(28, travel) }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.6).delay(0.18)) { offset = 0 }
    }
}

private struct DisabledDimmingModifier: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        content.opacity(isEnabled ? 1 : 0.4)
    }
}

#Preview {
    VStack(spacing: KWSpacing.md) {
        KWSwipeToConfirm("Slide to save expense") {}
        KWSwipeToConfirm("Slide to move") {}.disabled(true)
    }
    .padding(KWLayout.gutter)
    .background(KWColor.Surface.bg)
    .onAppear { KWFonts.register() }
}
