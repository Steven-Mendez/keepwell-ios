import SwiftUI

/// The design's 52×32 switch: label on the leading side, switch trailing. `tint` is the on color,
/// green by default and amber for "gasto previsto".
public struct KWToggleStyle: ToggleStyle {
    private let tint: Color

    public init(tint: Color = KWColor.State.positive) {
        self.tint = tint
    }

    public func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: KWSpacing.sm) {
            configuration.label
                .frame(maxWidth: .infinity, alignment: .leading)
            Capsule()
                .fill(configuration.isOn ? tint : KWColor.Surface.controlOff)
                .frame(width: KWComponentMetrics.switchSize.width, height: KWComponentMetrics.switchSize.height)
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Circle()
                        .fill(.white)
                        .frame(width: 26, height: 26)
                        .padding(3)
                }
                .animation(.snappy(duration: 0.2), value: configuration.isOn)
        }
        .contentShape(Rectangle())
        .onTapGesture { configuration.isOn.toggle() }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(configuration.isOn ? Text("Activado") : Text("Desactivado"))
        .accessibilityAction { configuration.isOn.toggle() }
    }
}

extension ToggleStyle where Self == KWToggleStyle {
    public static var kw: KWToggleStyle { KWToggleStyle() }

    public static func kw(tint: Color) -> KWToggleStyle {
        KWToggleStyle(tint: tint)
    }
}

#Preview {
    @Previewable @State var on = true
    @Previewable @State var planned = false
    VStack(spacing: KWSpacing.md) {
        Toggle("Respaldo en iCloud", isOn: $on).toggleStyle(.kw)
        Toggle("Es un gasto previsto", isOn: $planned).toggleStyle(.kw(tint: KWColor.State.pending))
    }
    .font(KWTextStyle.body.font)
    .foregroundStyle(KWColor.Text.primary)
    .padding(KWLayout.gutter)
    .background(KWColor.Surface.bg)
    .onAppear { KWFonts.register() }
}
