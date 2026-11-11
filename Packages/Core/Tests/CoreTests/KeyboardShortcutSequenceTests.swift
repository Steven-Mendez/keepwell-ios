import Foundation
import Testing
@testable import Core

struct KeyboardShortcutSequenceTests {
    private let start = Date(timeIntervalSince1970: 1000)

    static let singles: [(Character, ShortcutCommand)] = [
        ("n", ShortcutCommand.newMovement(.any)),
        ("e", .newMovement(.expense)),
        ("I", .newMovement(.income)),
        ("t", .newMovement(.transfer)),
        ("/", .search),
        ("?", .showShortcuts),
        (",", .goTo(.settings)),
        ("1", .goTo(.home)),
        ("2", .goTo(.transactions)),
        ("3", .goTo(.accounts)),
        ("4", .goTo(.summary)),
    ]

    static let jumps: [(Character, ShortcutDestination)] = [
        ("r", .recurring),
        ("g", .goals),
        ("d", .debts),
        ("h", .home),
        ("t", .transactions),
        ("a", .accounts),
        ("s", .summary),
        (",", .settings),
    ]

    @Test(arguments: singles)
    func singleKeys(key: Character, command: ShortcutCommand) {
        var sequence = KeyboardShortcutSequence()
        #expect(sequence.press(key, at: start) == .run(command))
    }

    @Test
    func unknownKeysAreLeftAlone() {
        var sequence = KeyboardShortcutSequence()
        #expect(sequence.press("x", at: start) == .ignored)
        #expect(sequence.press("5", at: start) == .ignored)
    }

    @Test(arguments: jumps)
    func gThenLetter(letter: Character, destination: ShortcutDestination) {
        var sequence = KeyboardShortcutSequence()
        #expect(sequence.press("g", at: start) == .pending)
        #expect(sequence.press(letter, at: start.addingTimeInterval(0.5)) == .run(.goTo(destination)))
    }

    @Test
    func theLetterAfterGIsNotAShortcutOnItsOwn() {
        var sequence = KeyboardShortcutSequence()
        _ = sequence.press("g", at: start)
        // "t" after "g" is Transactions, not a new transfer.
        #expect(sequence.press("t", at: start.addingTimeInterval(0.1)) == .run(.goTo(.transactions)))
        #expect(sequence.press("t", at: start.addingTimeInterval(0.2)) == .run(.newMovement(.transfer)))
    }

    @Test
    func anUnknownLetterAfterGEndsTheSequence() {
        var sequence = KeyboardShortcutSequence()
        _ = sequence.press("g", at: start)
        #expect(sequence.press("x", at: start.addingTimeInterval(0.1)) == .ignored)
        #expect(sequence.press("r", at: start.addingTimeInterval(0.2)) == .ignored)
    }

    @Test
    func gTimesOut() {
        var sequence = KeyboardShortcutSequence()
        _ = sequence.press("g", at: start)
        // Too late for the section letter, so "r" is just an unknown key.
        #expect(sequence.press("r", at: start.addingTimeInterval(1.3)) == .ignored)
    }

    @Test
    func aLateKeyStillRunsAsItself() {
        var sequence = KeyboardShortcutSequence()
        _ = sequence.press("g", at: start)
        #expect(sequence.press("n", at: start.addingTimeInterval(2)) == .run(.newMovement(.any)))
    }

    @Test
    func everyDestinationHasAUniqueLetter() {
        let keys = ShortcutDestination.allCases.map(\.jumpKey)
        #expect(Set(keys).count == keys.count)
    }
}
