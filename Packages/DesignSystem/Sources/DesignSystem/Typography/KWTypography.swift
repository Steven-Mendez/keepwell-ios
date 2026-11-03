import SwiftUI

public enum KWTextStyle: String, CaseIterable, Sendable {
    case display
    case amountLg
    case title
    case titleSm
    case amountSm
    case heading
    case body
    case label
    case caption
    case captionSm
    case micro

    public var size: CGFloat {
        switch self {
        case .display: 52
        case .amountLg: 40
        case .title: 30
        case .titleSm: 26
        case .amountSm: 20
        case .heading: 17
        case .body: 15
        case .label: 14
        case .caption: 13
        case .captionSm: 12
        case .micro: 11
        }
    }

    /// CSS weight (400…800).
    public var cssWeight: Int {
        switch self {
        case .display, .amountLg, .title, .titleSm, .amountSm: 800
        case .heading: 700
        case .body: 400
        case .label, .micro: 600
        case .caption, .captionSm: 500
        }
    }

    /// Tracking in points.
    public var tracking: CGFloat {
        switch self {
        case .display: -1.5
        case .amountLg: -1
        case .title, .titleSm: -0.5
        default: 0
        }
    }

    /// Amount styles: always use tabular figures.
    public var isNumeric: Bool {
        switch self {
        case .display, .amountLg, .amountSm: true
        default: false
        }
    }

    /// System text style it scales with under Dynamic Type.
    var relativeTo: Font.TextStyle {
        switch self {
        case .display, .amountLg: .largeTitle
        case .title: .title
        case .titleSm: .title2
        case .amountSm: .title3
        case .heading: .headline
        case .body: .body
        case .label: .subheadline
        case .caption: .footnote
        case .captionSm: .caption
        case .micro: .caption2
        }
    }

    public var font: Font {
        .custom(KWFonts.Weight(cssWeight: cssWeight).postScriptName, size: size, relativeTo: relativeTo)
    }
}

extension View {
    /// Amount styles get tabular figures by default so columns of numbers line up.
    public func kwTextStyle(_ style: KWTextStyle, monospacedDigits: Bool? = nil) -> some View {
        font(style.font)
            .tracking(style.tracking)
            .monospacedDigit(monospacedDigits ?? style.isNumeric)
    }
}

extension View {
    @ViewBuilder
    private func monospacedDigit(_ enabled: Bool) -> some View {
        if enabled {
            monospacedDigit()
        } else {
            self
        }
    }
}
