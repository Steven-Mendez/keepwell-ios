import SwiftUI

/// Moves focus through a form's fields in reading order. Forms pass only the fields on screen,
/// since rows come and go (a second currency, a dual-debt amount).
public enum KWFocusOrder {
    /// The field `offset` steps from `current`, or `nil` past either end or when `current` is not
    /// in `order`.
    public static func field<Field: Equatable>(_ offset: Int, from current: Field?, in order: [Field]) -> Field? {
        guard let current, let index = order.firstIndex(of: current) else { return nil }
        let target = index + offset
        return order.indices.contains(target) ? order[target] : nil
    }
}

extension View {
    /// Previous / next arrows and "Done" on top of the keyboard when the form has several fields,
    /// plus return advancing to the next field. Number and decimal pads have no return key, so
    /// without this the only way to the next field was finding it and tapping it.
    ///
    /// Drawn as a bottom inset rather than a `.keyboard` toolbar: those only render inside a
    /// `NavigationStack`, and the form sheets have none. The inset sits on the keyboard, under a
    /// `KWFormScreen` footer, and only while one of `order`'s fields has focus.
    public func kwKeyboardToolbar<Field: Hashable>(_ focus: FocusState<Field?>.Binding, order: [Field]) -> some View {
        modifier(KWKeyboardToolbarModifier(focus: focus, order: order))
    }
}

extension View {
    /// `focused(_:equals:)` that also tags the row, so `KWFormScreen` can scroll it into view.
    public func kwFocused<Field: Hashable>(_ focus: FocusState<Field?>.Binding, equals field: Field) -> some View {
        // The tag lives on a background: containers such as `KWGroupedCard` rebuild their rows
        // from subviews, which takes a row's own `id` as its identity instead of a scroll target.
        focused(focus, equals: field).background { Color.clear.id(AnyHashable(field)) }
    }
}

private struct KWKeyboardToolbarModifier<Field: Hashable>: ViewModifier {
    let focus: FocusState<Field?>.Binding
    let order: [Field]

    func body(content: Content) -> some View {
        content
            .submitLabel(.next)
            .onSubmit { focus.wrappedValue = KWFocusOrder.field(1, from: focus.wrappedValue, in: order) }
            .environment(\.kwFocusedField, focus.wrappedValue.map(AnyHashable.init))
            .safeAreaInset(edge: .bottom, spacing: 0) {
                // One field needs no navigation: the footer's action already rides on the keyboard.
                if order.count > 1, let current = focus.wrappedValue, order.contains(current) {
                    bar
                }
            }
    }

    private var bar: some View {
        HStack(spacing: KWSpacing.xxs) {
            arrow(.up, offset: -1, label: Text("Previous field", bundle: #bundle))
            arrow(.down, offset: 1, label: Text("Next field", bundle: #bundle))
            Spacer()
            Button { focus.wrappedValue = nil } label: {
                Text("Done", bundle: #bundle)
                    .font(.kw(15, weight: 700))
                    .foregroundStyle(KWColor.Brand.link)
                    .padding(.horizontal, KWSpacing.md)
                    .frame(minHeight: KWLayout.minTouch)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, KWSpacing.xxs)
        .background(KWColor.Surface.nav)
        .overlay(alignment: .top) { KWDivider() }
    }

    private enum Direction { case up, down }

    private func arrow(_ direction: Direction, offset: Int, label: Text) -> some View {
        let target = KWFocusOrder.field(offset, from: focus.wrappedValue, in: order)
        return Button { focus.wrappedValue = target } label: {
            Image(systemName: direction == .up ? "chevron.up" : "chevron.down")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(target == nil ? KWColor.Text.faint : KWColor.Text.primary)
                .frame(width: KWLayout.minTouch, height: KWLayout.minTouch)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(target == nil)
        .accessibilityLabel(label)
    }
}
