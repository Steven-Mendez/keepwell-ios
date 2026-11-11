import Core
import SharedPresentation
import SwiftUI

extension RootView {
    // MARK: - Keyboard

    /// False while a flow, sheet or the lock owns the screen, like the web's open dialog: the keys
    /// are then left alone.
    var ownsKeyboard: Bool {
        !lock.isLocked && !showsShortcuts && newMovement == nil && addCard == nil && movementMenu == nil
            && splitBill == nil && !choosingSyncData.wrappedValue
    }

    /// Hidden so the key shows up in the iPad's ⌘-hold list without drawing anything.
    var keyboardShortcutButtons: some View {
        Button(ShortcutCommandDisplay.title(of: .search)) {
            if ownsKeyboard {
                perform(.search)
            }
        }
        .keyboardShortcut("k", modifiers: .command)
        .frame(width: 0, height: 0)
        .clipped()
        .opacity(0)
        .accessibilityHidden(true)
    }

    func handleKey(_ press: KeyPress) -> KeyPress.Result {
        guard ownsKeyboard, !TextInputFocus.isEditing,
              press.modifiers.isDisjoint(with: [.command, .control, .option]),
              press.characters.count == 1, let key = press.characters.first
        else { return .ignored }
        switch keySequence.press(key) {
        case .ignored:
            return .ignored
        case .pending:
            return .handled
        case let .run(command):
            perform(command)
            return .handled
        }
    }

    /// Runs a shortcut, a search suggestion or a Settings row, resolving the stack first so a
    /// destination never opens on top of another screen.
    func perform(_ command: ShortcutCommand) {
        switch command {
        case .search:
            if let screens {
                navigator.path = NavigationPath()
                focusSearch(screens)
            }
        case let .newMovement(kind):
            switch kind {
            case .any: presentMovementMenu()
            case .expense: presentNewMovement(.expense)
            case .income: presentNewMovement(.income)
            case .transfer: presentNewMovement(.transfer)
            }
        case let .goTo(destination):
            go(to: destination)
        case .showShortcuts:
            showsShortcuts = true
        }
    }

    private func go(to destination: ShortcutDestination) {
        navigator.path = NavigationPath()
        switch destination {
        case .home: tab = .home
        case .transactions: tab = .transactions
        case .accounts: tab = .accounts
        case .summary: tab = .summary
        case .recurring: navigator.push(.recurring)
        case .goals: navigator.push(.goals)
        case .debts: navigator.push(.debts)
        case .settings: navigator.push(.settings)
        }
    }

    func focusSearch(_ screens: MainScreens) {
        screens.transactions.filter = .all
        screens.transactions.scope = .all
        screens.transactions.wantsSearchFocus = true
        tab = .transactions
    }
}

extension View {
    /// Wires the hardware keyboard into the app: plain keys, ⌘K and the list behind "?".
    func rootKeyboard(_ root: RootView) -> some View {
        focusable()
            .focused(root.$hasKeyboardFocus)
            .focusEffectDisabled()
            .onKeyPress(phases: .down, action: root.handleKey)
            .background { root.keyboardShortcutButtons }
            .onAppear { root.hasKeyboardFocus = true }
            .onChange(of: root.ownsKeyboard) { _, owns in
                if owns {
                    root.hasKeyboardFocus = true
                }
            }
            .sheet(isPresented: root.$showsShortcuts) {
                KeyboardShortcutsSheet { root.showsShortcuts = false }
                    .presentationDetents([.large])
            }
    }
}
