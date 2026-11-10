import SwiftUI

/// The tinted square behind a settings row's icon, as in the iPhone's own Settings.
public struct KWSettingsIcon: View {
    private let icon: KWIcon
    private let tint: Color
    @ScaledMetric(relativeTo: .body) private var side: CGFloat = 30

    public init(_ icon: KWIcon, tint: Color) {
        self.icon = icon
        self.tint = tint
    }

    public var body: some View {
        KWIconView(icon, size: side * 0.6, lineWidth: 2.2)
            .foregroundStyle(.white)
            .frame(width: side, height: side)
            .background(tint, in: RoundedRectangle(cornerRadius: side * 0.27, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// What sits at a settings row's trailing edge.
public enum KWSettingsAccessory: Equatable, Sendable {
    /// Opens a screen or a choice inside the app.
    case chevron
    /// Leaves the app (a web page, the iPhone's Settings).
    case external
}

/// A settings row: tinted icon, a title with an optional one-line description under it, then an
/// optional value and the accessory. Destructive rows are red, without an icon tile, so they read
/// apart from everything above them. At accessibility text sizes the value moves under the title
/// instead of squeezing it.
public struct KWSettingsRow<Trailing: View>: View {
    private let title: String
    private let description: String?
    private let icon: KWIcon?
    private let tint: Color
    private let value: String?
    private let accessory: KWSettingsAccessory?
    private let isDestructive: Bool
    private let trailing: Trailing
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    public init(
        _ title: String,
        description: String? = nil,
        icon: KWIcon? = nil,
        tint: Color = KWColor.Brand.b500,
        value: String? = nil,
        accessory: KWSettingsAccessory? = nil,
        isDestructive: Bool = false,
        @ViewBuilder trailing: () -> Trailing,
    ) {
        self.title = title
        self.description = description
        self.icon = icon
        self.tint = tint
        self.value = value
        self.accessory = accessory
        self.isDestructive = isDestructive
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(spacing: KWSpacing.sm) {
            if let icon {
                KWSettingsIcon(icon, tint: isDestructive ? KWColor.State.negative : tint)
            }
            if dynamicTypeSize.isAccessibilitySize {
                // Values and controls go under the title, which keeps the whole width.
                VStack(alignment: .leading, spacing: KWSpacing.xxs) {
                    titleBlock
                    valueText
                    trailing
                }
                Spacer(minLength: 0)
            } else {
                titleBlock
                Spacer(minLength: KWSpacing.xs)
                valueText
                trailing
            }
            accessoryView
        }
        .padding(.vertical, description == nil ? 13 : 11)
        .frame(minHeight: KWLayout.minTouch)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(KWTextStyle.body.font.weight(isDestructive ? .semibold : .regular))
                .foregroundStyle(isDestructive ? KWColor.State.negative : KWColor.Text.primary)
                .fixedSize(horizontal: false, vertical: true)
            if let description {
                Text(description)
                    .font(KWTextStyle.captionSm.font.weight(.regular))
                    .foregroundStyle(KWColor.Text.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .layoutPriority(1)
    }

    @ViewBuilder
    private var valueText: some View {
        if let value {
            Text(value)
                .font(KWTextStyle.body.font)
                .foregroundStyle(KWColor.Text.muted)
                .monospacedDigit()
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                // A long currency name shrinks a little before it truncates; a short value (a count,
                // "3 days") never gives way to the title.
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: value.count <= 12 && !dynamicTypeSize.isAccessibilitySize, vertical: false)
                .multilineTextAlignment(dynamicTypeSize.isAccessibilitySize ? .leading : .trailing)
        }
    }

    @ViewBuilder
    private var accessoryView: some View {
        switch accessory {
        case nil:
            EmptyView()
        case .chevron:
            KWIconView(.chevronRight, size: 16, lineWidth: 2.4)
                .foregroundStyle(KWColor.Text.faint)
        case .external:
            KWIconView(.externalLink, size: 15, lineWidth: 2.2)
                .foregroundStyle(KWColor.Text.faint)
                .accessibilityLabel(Text("Opens outside Keepwell", bundle: #bundle))
        }
    }
}

extension KWSettingsRow where Trailing == EmptyView {
    public init(
        _ title: String,
        description: String? = nil,
        icon: KWIcon? = nil,
        tint: Color = KWColor.Brand.b500,
        value: String? = nil,
        accessory: KWSettingsAccessory? = nil,
        isDestructive: Bool = false,
    ) {
        self.init(
            title, description: description, icon: icon, tint: tint, value: value, accessory: accessory,
            isDestructive: isDestructive,
        ) { EmptyView() }
    }
}

/// A person's initial on the brand blue, or the person glyph when there's no name.
public struct KWAvatar: View {
    private let name: String?
    @ScaledMetric(relativeTo: .title) private var side: CGFloat = 52

    public init(name: String?) {
        self.name = name
    }

    public var body: some View {
        Group {
            if let initial = name?.trimmingCharacters(in: .whitespaces).first {
                Text(String(initial).uppercased())
                    .font(.kw(22, weight: 700, relativeTo: .title2))
            } else {
                KWIconView(.person, size: side * 0.45)
            }
        }
        .foregroundStyle(.white)
        .frame(width: side, height: side)
        .background(KWColor.Brand.b500, in: Circle())
        .accessibilityHidden(true)
    }
}

/// The tints of the settings icons, one per kind of setting, readable with a white glyph in both
/// appearances.
public enum KWSettingsTint {
    public static let account = KWColor.Brand.b500
    public static let profile = Color(hex: 0x8E5CF7)
    public static let money = Color(hex: 0x17A673)
    public static let reminders = Color(hex: 0xF2994A)
    public static let organization = Color(hex: 0x2D9CDB)
    public static let data = Color(hex: 0x5B6CF0)
    public static let security = Color(hex: 0x4F5568)
    public static let assistants = Color(hex: 0xD9773F)
    public static let about = Color(hex: 0x8A8A96)
}

#Preview {
    VStack(spacing: KWSpacing.md) {
        KWGroupedCard {
            KWSettingsRow("Your name", description: "For the greeting", icon: .person, tint: KWSettingsTint.profile, value: "Steven")
            KWSettingsRow("App language", icon: .globe, tint: KWSettingsTint.profile, value: "English", accessory: .external)
            KWSettingsRow("Expense categories", icon: .tag, tint: KWSettingsTint.organization, value: "23", accessory: .chevron)
        }
        KWGroupedCard {
            KWSettingsRow("Sign out", icon: .logOut, isDestructive: true)
        }
    }
    .padding(KWLayout.gutter)
    .background(KWColor.Surface.bg)
    .onAppear { KWFonts.register() }
}
