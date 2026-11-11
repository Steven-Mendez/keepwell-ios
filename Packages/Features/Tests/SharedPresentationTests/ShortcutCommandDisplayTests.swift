import Core
import Testing
@testable import SharedPresentation

struct ShortcutCommandDisplayTests {
    @Test
    func emptyQueryOffersEverything() {
        #expect(ShortcutCommandDisplay.suggestions(for: "", in: ShortcutCommand.actions).count == 8)
        #expect(ShortcutCommandDisplay.suggestions(for: "  ", in: ShortcutCommand.destinations).count == 8)
    }

    @Test
    func queryNarrowsByTitleIgnoringCase() {
        let found = ShortcutCommandDisplay.suggestions(for: "GOAL", in: ShortcutCommand.destinations)
        #expect(found == [.goTo(.goals)])
        #expect(ShortcutCommandDisplay.suggestions(for: "new", in: ShortcutCommand.actions).count == 3)
        #expect(ShortcutCommandDisplay.suggestions(for: "keyboard", in: ShortcutCommand.actions) == [.showShortcuts])
        #expect(ShortcutCommandDisplay.suggestions(for: "rules", in: ShortcutCommand.actions) == [.rules])
    }

    @Test
    func noMatchOffersNothing() {
        #expect(ShortcutCommandDisplay.suggestions(for: "zzz", in: ShortcutCommand.destinations).isEmpty)
    }

    @Test
    func goToKeysFollowTheWeb() {
        #expect(ShortcutCommandDisplay.keys(of: .home) == ["1"])
        #expect(ShortcutCommandDisplay.keys(of: .recurring) == ["G", "R"])
        #expect(ShortcutCommandDisplay.keys(of: .settings) == [","])
    }

    @Test
    func listHasOneRowPerShortcut() {
        let rows = ShortcutCommandDisplay.shortcutRows
        // ⌘K, N, E, I, T, /, four digits, eight "G" jumps and "?".
        #expect(rows.count == 6 + 4 + 8 + 1)
        #expect(rows.first?.keys == ["⌘", "K"])
        #expect(rows.last?.keys == ["?"])
    }
}
