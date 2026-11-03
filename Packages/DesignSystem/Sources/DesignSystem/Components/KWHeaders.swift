import SwiftUI

/// 40pt round icon button used for back, close and "+" in headers.
public struct KWCircleButton: View {
    public enum Style: Sendable {
        /// `surface` fill on black screens.
        case surface
        /// Translucent white on gradients.
        case translucent
        /// White fill, black icon: the "+" in list headers.
        case white
    }

    private let icon: KWIcon
    private let style: Style
    private let accessibilityLabel: String
    private let action: () -> Void

    public init(_ icon: KWIcon, style: Style = .surface, accessibilityLabel: String, action: @escaping () -> Void) {
        self.icon = icon
        self.style = style
        self.accessibilityLabel = accessibilityLabel
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            KWIconView(icon, size: 20, lineWidth: style == .white ? 2.2 : 2)
                .foregroundStyle(style == .white ? Color.black : KWColor.Text.primary)
                .frame(width: 40, height: 40)
                .background(background, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private var background: Color {
        switch style {
        case .surface: KWColor.Surface.surface
        case .translucent: KWColor.Overlay.white14
        case .white: .white
        }
    }
}

/// Segmented progress for multi-step flows: done steps white, pending ones `border`.
public struct KWStepProgress: View {
    private let total: Int
    private let current: Int

    /// `current` is 1-based: the number of filled segments.
    public init(total: Int, current: Int) {
        self.total = total
        self.current = current
    }

    public var body: some View {
        HStack(spacing: 6) {
            ForEach(0 ..< total, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(index < current ? Color.white : KWColor.Surface.border)
                    .frame(height: 4)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Paso \(current) de \(total)")
    }
}

/// Flow header: back or close button, then the step progress when the step counts.
public struct KWFlowHeader: View {
    public enum Leading: Sendable {
        case back
        case close
    }

    private let leading: Leading
    private let progress: (total: Int, current: Int)?
    private let action: () -> Void

    public init(_ leading: Leading, progress: (total: Int, current: Int)? = nil, action: @escaping () -> Void) {
        self.leading = leading
        self.progress = progress
        self.action = action
    }

    public var body: some View {
        HStack(spacing: KWSpacing.sm) {
            KWCircleButton(
                leading == .back ? .chevronLeft : .close,
                accessibilityLabel: leading == .back ? "Atrás" : "Cerrar",
                action: action,
            )
            if let progress {
                KWStepProgress(total: progress.total, current: progress.current)
            } else {
                Spacer()
            }
        }
    }
}

/// Tab screen header: 30pt title, optional subtitle content and a trailing action.
public struct KWLargeTitleHeader<Subtitle: View, Trailing: View>: View {
    private let title: String
    private let subtitle: Subtitle
    private let trailing: Trailing

    public init(_ title: String, @ViewBuilder subtitle: () -> Subtitle, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.subtitle = subtitle()
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .kwTextStyle(.title)
                    .foregroundStyle(KWColor.Text.primary)
                    .accessibilityAddTraits(.isHeader)
                subtitle
            }
            Spacer(minLength: KWSpacing.xs)
            trailing
        }
    }
}

extension KWLargeTitleHeader where Subtitle == EmptyView {
    public init(_ title: String, @ViewBuilder trailing: () -> Trailing) {
        self.init(title, subtitle: { EmptyView() }, trailing: trailing)
    }
}

/// Pushed screen header: back button with a centered title, or a leading title and subtitle.
public struct KWNavigationHeader: View {
    public enum Style: Sendable {
        /// 17/700 title centered across the screen ("Mastercard ··1234").
        case centered
        /// 17/700 title with a 13pt subtitle next to the button.
        case leading
        /// 26/800 title next to the button ("Ajustes").
        case large
    }

    private let title: String
    private let subtitle: String?
    private let style: Style
    private let buttonStyle: KWCircleButton.Style
    private let onBack: () -> Void

    public init(
        _ title: String,
        subtitle: String? = nil,
        style: Style = .centered,
        buttonStyle: KWCircleButton.Style = .surface,
        onBack: @escaping () -> Void,
    ) {
        self.title = title
        self.subtitle = subtitle
        self.style = style
        self.buttonStyle = buttonStyle
        self.onBack = onBack
    }

    public var body: some View {
        HStack(spacing: KWSpacing.sm) {
            KWCircleButton(.chevronLeft, style: buttonStyle, accessibilityLabel: "Volver", action: onBack)
            switch style {
            case .centered:
                Text(title)
                    .font(KWTextStyle.heading.font)
                    .frame(maxWidth: .infinity)
                    // Balances the back button so the title centers on the screen.
                    .padding(.trailing, 52)
            case .leading:
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).font(KWTextStyle.heading.font)
                    if let subtitle {
                        Text(subtitle)
                            .font(KWTextStyle.caption.font)
                            .foregroundStyle(KWColor.Text.muted)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            case .large:
                Text(title)
                    .kwTextStyle(.titleSm)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .lineLimit(1)
        .foregroundStyle(KWColor.Text.primary)
        .accessibilityElement(children: .contain)
    }
}

#Preview {
    VStack(spacing: KWSpacing.xl) {
        KWFlowHeader(.close, progress: (4, 1)) {}
        KWLargeTitleHeader("Movimientos") {
            KWCircleButton(.plus, style: .white, accessibilityLabel: "Nuevo movimiento") {}
        }
        KWNavigationHeader("Mastercard ··1234") {}
        KWNavigationHeader("Familiar", subtitle: "Adicional de Mastercard ··1234", style: .leading) {}
        KWNavigationHeader("Ajustes", style: .large) {}
    }
    .padding(KWLayout.gutter)
    .background(KWColor.Surface.bg)
    .onAppear { KWFonts.register() }
}
