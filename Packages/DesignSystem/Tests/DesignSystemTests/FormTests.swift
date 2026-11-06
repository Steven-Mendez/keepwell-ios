import SwiftUI
import Testing
@testable import DesignSystem

@Suite("Forms")
@MainActor
struct FormTests {
    private enum Field { case bank, name, balance }

    private let order: [Field] = [.bank, .name, .balance]

    @Test
    func nextAndPreviousFollowTheOrderOnScreen() {
        #expect(KWFocusOrder.field(1, from: .bank, in: order) == .name)
        #expect(KWFocusOrder.field(-1, from: .balance, in: order) == .name)
    }

    @Test
    func stopsAtEitherEnd() {
        #expect(KWFocusOrder.field(1, from: .balance, in: order) == nil)
        #expect(KWFocusOrder.field(-1, from: .bank, in: order) == nil)
    }

    @Test
    func nothingToMoveFromWhenNoFieldOnScreenHasFocus() {
        #expect(KWFocusOrder.field(1, from: nil, in: order) == nil)
        #expect(KWFocusOrder.field(1, from: .name, in: [Field.bank, .balance]) == nil)
    }

    @Test
    func footerRidesJustAboveTheKeyboard() {
        let padding = KWFormScreen<EmptyView, EmptyView>.footerBottomPadding(bottom: 24, safeBottom: 336, containerBottom: 34)
        #expect(padding == KWSpacing.sm)
    }

    @Test
    func footerKeepsTheDesignMarginWithoutTheKeyboard() {
        // 40pt from the physical edge on a phone with a 34pt home indicator inset.
        #expect(KWFormScreen<EmptyView, EmptyView>.footerBottomPadding(bottom: 40, safeBottom: 34, containerBottom: 34) == 6)
        // Never under the home indicator when the design margin is smaller than the inset.
        #expect(KWFormScreen<EmptyView, EmptyView>.footerBottomPadding(bottom: 24, safeBottom: 34, containerBottom: 34) == 0)
    }

    @Test(arguments: [("1234", "1234"), ("12345", "1234"), ("•• 98 7", "987"), ("abc", ""), ("١٢٣٤", "")])
    func cardEndingsKeepOnlyTheFirstDigits(text: String, expected: String) {
        #expect(KWTextFieldRow.digits(text, limit: 4) == expected)
    }

    @Test
    func fieldRows() {
        let view = KWGroupedCard {
            KWTextFieldRow("Bank", placeholder: "Bank name", text: .constant("LAFISE"))
            KWTextFieldRow("Debit, last 4", placeholder: "Optional", text: .constant(""), digitLimit: 4, width: 110)
            KWAmountFieldRow("Today's balance", symbol: "C$", text: .constant("10,000.00"))
            KWAmountFieldRow("USD the bank charged you", hint: "Optional · if it used another rate", symbol: "$", text: .constant(""))
        }
        .padding(KWLayout.gutter)
        assertComponentSnapshot(of: view, height: 300)
    }
}
