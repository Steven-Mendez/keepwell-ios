import SwiftUI

/// One dot per passcode digit, filled as they're typed. Red while showing a wrong entry.
public struct KWPasscodeDots: View {
    private let length: Int
    private let filled: Int
    private let isError: Bool

    public init(length: Int, filled: Int, isError: Bool = false) {
        self.length = length
        self.filled = filled
        self.isError = isError
    }

    public var body: some View {
        HStack(spacing: 18) {
            ForEach(0 ..< length, id: \.self) { index in
                Circle()
                    .fill(index < filled ? fill : KWColor.Text.primary.opacity(0.18))
                    .frame(width: 14, height: 14)
                    .scaleEffect(index < filled ? 1.1 : 1)
            }
        }
        .animation(.snappy(duration: 0.15), value: filled)
        .accessibilityElement()
        .accessibilityValue(Text("\(filled) of \(length) digits", bundle: .module))
    }

    private var fill: Color {
        isError ? KWColor.State.negative : KWColor.Text.primary
    }
}

/// The 3×4 number pad of the lock and passcode screens. The bottom-left key is the caller's
/// (Face ID, or nothing); the bottom-right one deletes. `isEnabled` covers the digits and delete
/// only, so the caller's key can stay usable while typing is paused.
public struct KWKeypad<Accessory: View>: View {
    private let isEnabled: Bool
    private let onDigit: (Int) -> Void
    private let onDelete: () -> Void
    private let accessory: Accessory

    public init(
        isEnabled: Bool = true,
        onDigit: @escaping (Int) -> Void,
        onDelete: @escaping () -> Void,
        @ViewBuilder accessory: () -> Accessory,
    ) {
        self.isEnabled = isEnabled
        self.onDigit = onDigit
        self.onDelete = onDelete
        self.accessory = accessory()
    }

    public var body: some View {
        Grid(horizontalSpacing: KWSpacing.lg, verticalSpacing: KWSpacing.sm) {
            ForEach(0 ..< 3, id: \.self) { row in
                GridRow {
                    ForEach(1 ... 3, id: \.self) { column in
                        digit(row * 3 + column)
                    }
                }
            }
            GridRow {
                accessory.frame(width: Self.key, height: Self.key)
                digit(0)
                Button(action: onDelete) {
                    KWIconView(.chevronLeft, size: 26)
                        .frame(width: Self.key, height: Self.key)
                        .contentShape(Circle())
                }
                .buttonStyle(KWKeyStyle(filled: false))
                .accessibilityLabel(Text("Delete", bundle: .module))
                .disabled(!isEnabled)
                .opacity(isEnabled ? 1 : 0.35)
            }
        }
    }

    static var key: CGFloat {
        76
    }

    private func digit(_ value: Int) -> some View {
        Button { onDigit(value) } label: {
            Text(verbatim: "\(value)")
                .font(.kw(30, weight: 600, relativeTo: .title))
                .monospacedDigit()
                .frame(width: Self.key, height: Self.key)
                .contentShape(Circle())
        }
        .buttonStyle(KWKeyStyle(filled: true))
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.35)
    }
}

extension KWKeypad where Accessory == Color {
    public init(isEnabled: Bool = true, onDigit: @escaping (Int) -> Void, onDelete: @escaping () -> Void) {
        self.init(isEnabled: isEnabled, onDigit: onDigit, onDelete: onDelete) { Color.clear }
    }
}

/// A round key that lights up while pressed, like the system passcode pad.
public struct KWKeyStyle: ButtonStyle {
    private let filled: Bool

    public init(filled: Bool) {
        self.filled = filled
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(KWColor.Text.primary)
            .background(background(isPressed: configuration.isPressed), in: Circle())
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private func background(isPressed: Bool) -> Color {
        if isPressed {
            return KWColor.Text.primary.opacity(0.18)
        }
        return filled ? KWColor.Text.primary.opacity(0.10) : .clear
    }
}

/// Horizontal shake for a rejected entry. Each change of `trigger` plays it once.
public struct KWShakeEffect: GeometryEffect {
    public var animatableData: CGFloat

    public init(trigger: Int) {
        animatableData = CGFloat(trigger)
    }

    public func effectValue(size _: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 10 * sin(animatableData * .pi * 4), y: 0))
    }
}

extension View {
    /// Shakes the view each time `trigger` changes.
    public func kwShake(_ trigger: Int) -> some View {
        modifier(KWShakeEffect(trigger: trigger))
            .animation(.linear(duration: 0.4), value: trigger)
    }
}
