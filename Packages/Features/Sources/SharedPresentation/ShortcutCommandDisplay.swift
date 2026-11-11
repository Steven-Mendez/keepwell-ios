import Core
import DesignSystem
import Foundation
import SwiftUI

/// Names and key caps of the keyboard commands, in the web's words ("New expense", "Go to"…).
public enum ShortcutCommandDisplay {
    public static func title(of command: ShortcutCommand) -> String {
        switch command {
        case .search: String(localized: "Command palette", bundle: #bundle)
        case .newMovement(.any): String(localized: "Log transaction", bundle: #bundle)
        case .newMovement(.expense): String(localized: "New expense", bundle: #bundle)
        case .newMovement(.income): String(localized: "New income", bundle: #bundle)
        case .newMovement(.transfer): String(localized: "New transfer", bundle: #bundle)
        case let .goTo(destination): title(of: destination)
        case .showShortcuts: String(localized: "Show shortcuts", bundle: #bundle)
        }
    }

    public static func title(of destination: ShortcutDestination) -> String {
        switch destination {
        case .home: String(localized: "Home", bundle: #bundle)
        case .transactions: String(localized: "Transactions", bundle: #bundle)
        case .accounts: String(localized: "Accounts", bundle: #bundle)
        case .summary: String(localized: "Summary", bundle: #bundle)
        case .recurring: String(localized: "Recurring", bundle: #bundle)
        case .goals: String(localized: "Goals", bundle: #bundle)
        case .debts: String(localized: "Debts", bundle: #bundle)
        case .settings: String(localized: "Settings", bundle: #bundle)
        }
    }

    public static func symbol(of command: ShortcutCommand) -> String {
        switch command {
        case .search: "magnifyingglass"
        case .newMovement(.expense): "arrow.up.right"
        case .newMovement(.income): "arrow.down.left"
        case .newMovement(.transfer): "arrow.left.arrow.right"
        case .newMovement(.any): "plus"
        case let .goTo(destination): symbol(of: destination)
        case .showShortcuts: "keyboard"
        }
    }

    private static func symbol(of destination: ShortcutDestination) -> String {
        switch destination {
        case .home: "house"
        case .transactions: "list.bullet"
        case .accounts: "creditcard"
        case .summary: "chart.bar"
        case .recurring: "repeat"
        case .goals: "target"
        case .debts: "hand.raised"
        case .settings: "gearshape"
        }
    }

    /// The keys of a "Go to" row: the tab's digit, "G" then the letter for a section, "," for Settings.
    public static func keys(of destination: ShortcutDestination) -> [String] {
        if let digit = destination.digit {
            return [String(digit)]
        }
        if destination == .settings {
            return [","]
        }
        return ["G", String(destination.jumpKey).uppercased()]
    }

    /// Every shortcut with its key caps, in the web's list order. The web's sidebar and panel keys
    /// (⌘B, J K, Esc) have no counterpart on the iPhone and iPad, so they're not listed.
    public static var shortcutRows: [(keys: [String], title: String)] {
        var rows: [(keys: [String], title: String)] = [
            (["⌘", "K"], title(of: .search)),
            (["N"], title(of: .newMovement(.any))),
            (["E"], title(of: .newMovement(.expense))),
            (["I"], title(of: .newMovement(.income))),
            (["T"], title(of: .newMovement(.transfer))),
            (["/"], String(localized: "Focus search", bundle: #bundle)),
        ]
        rows += ShortcutDestination.allCases.compactMap { destination in
            destination.digit.map { ([String($0)], title(of: destination)) }
        }
        rows += ShortcutDestination.allCases.map { (["G", String($0.jumpKey).uppercased()], title(of: $0)) }
        rows.append((["?"], title(of: .showShortcuts)))
        return rows
    }

    /// Whether a title answers what was typed in search, ignoring case and accents.
    public static func matches(_ title: String, query: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespaces)
        return needle.isEmpty || title.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    /// The suggestions that answer `query`: all of them while it is empty.
    public static func suggestions(
        for query: String,
        in commands: [ShortcutCommand],
    ) -> [ShortcutCommand] {
        commands.filter { matches(title(of: $0), query: query) }
    }
}

/// A key cap: "⌘", "K", "G"…
struct KeyCap: View {
    let text: String

    var body: some View {
        Text(text)
            .font(KWTextStyle.captionSm.font)
            .monospaced()
            .foregroundStyle(KWColor.Text.secondary)
            .frame(minWidth: 24, minHeight: 24)
            .padding(.horizontal, 4)
            .background(KWColor.Surface.surface2, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

struct KeyCaps: View {
    let keys: [String]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                KeyCap(text: key)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(keys.joined(separator: " ")))
    }
}

/// "Actions" and "Go to" of the web's command palette, offered under the search field while it is
/// empty or what was typed matches them.
public struct CommandSuggestions: View {
    private let query: String
    private let onSelect: (ShortcutCommand) -> Void

    public init(query: String, onSelect: @escaping (ShortcutCommand) -> Void) {
        self.query = query
        self.onSelect = onSelect
    }

    public var body: some View {
        let actions = ShortcutCommandDisplay.suggestions(for: query, in: ShortcutCommand.actions)
        let destinations = ShortcutCommandDisplay.suggestions(for: query, in: ShortcutCommand.destinations)
        if !actions.isEmpty || !destinations.isEmpty {
            VStack(alignment: .leading, spacing: KWSpacing.sm) {
                section(String(localized: "Actions", bundle: #bundle), actions)
                section(String(localized: "Go to", bundle: #bundle), destinations)
            }
        }
    }

    @ViewBuilder
    private func section(_ title: String, _ commands: [ShortcutCommand]) -> some View {
        if !commands.isEmpty {
            VStack(alignment: .leading, spacing: KWSpacing.xs) {
                Text(title)
                    .font(KWTextStyle.label.font)
                    .foregroundStyle(KWColor.Text.muted)
                    .accessibilityAddTraits(.isHeader)
                KWGroupedCard {
                    ForEach(commands, id: \.self) { command in
                        Button { onSelect(command) } label: { row(command) }
                            .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func row(_ command: ShortcutCommand) -> some View {
        HStack(spacing: KWSpacing.sm) {
            Image(systemName: ShortcutCommandDisplay.symbol(of: command))
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(KWColor.Text.secondary)
                .frame(width: 24)
                .accessibilityHidden(true)
            Text(ShortcutCommandDisplay.title(of: command))
                .font(KWTextStyle.body.font)
                .foregroundStyle(KWColor.Text.primary)
            Spacer(minLength: KWSpacing.xs)
            KeyCaps(keys: keys(of: command))
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private func keys(of command: ShortcutCommand) -> [String] {
        switch command {
        case let .goTo(destination): ShortcutCommandDisplay.keys(of: destination)
        case .newMovement(.expense): ["E"]
        case .newMovement(.income): ["I"]
        case .newMovement(.transfer): ["T"]
        default: []
        }
    }
}

/// The list behind "?" and Settings › Keyboard shortcuts, as the web's dialog.
public struct KeyboardShortcutsSheet: View {
    private let onClose: () -> Void

    public init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KWSpacing.xs) {
                HStack {
                    Text("Keyboard shortcuts", bundle: #bundle)
                        .kwTextStyle(.titleSm)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    KWCircleButton(.close, accessibilityLabel: String(localized: "Close", bundle: #bundle), action: onClose)
                }
                .padding(.bottom, KWSpacing.xs)
                KWGroupedCard {
                    ForEach(Array(ShortcutCommandDisplay.shortcutRows.enumerated()), id: \.offset) { _, row in
                        HStack(spacing: KWSpacing.sm) {
                            Text(row.title)
                                .font(KWTextStyle.body.font)
                                .foregroundStyle(KWColor.Text.primary)
                            Spacer(minLength: KWSpacing.xs)
                            KeyCaps(keys: row.keys)
                        }
                        .padding(.vertical, 12)
                    }
                }
            }
            .padding(.horizontal, KWLayout.gutter)
            .padding(.top, KWSpacing.lg)
            .padding(.bottom, KWSpacing.lg)
        }
        .foregroundStyle(KWColor.Text.primary)
        .presentationBackground(KWColor.Surface.bg)
    }
}
