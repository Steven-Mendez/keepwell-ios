import SwiftUI
import Testing
@testable import DesignSystem

@Suite("Card art snapshots")
@MainActor
struct CardArtSnapshotTests {
    @Test
    func holderCardHasCreditCardRatio() {
        let card = KWCardArt(
            palette: .azul,
            bank: "Bank One",
            badge: .amount("−C$197.02 · −$16.79"),
            caption: "Credit · 2 cards",
            lastFour: "1234",
            network: .mastercard,
            kindLabel: "Credit",
        )
        assertComponentSnapshot(of: card.padding(KWLayout.gutter), height: 290)
    }

    @Test
    func paletteAndStateVariants() {
        let view = VStack(spacing: KWSpacing.xl) {
            KWCardArt(
                palette: .lima,
                bank: "Bank One",
                badge: .tag("Additional"),
                holder: "Family",
                lastFour: "5678",
                network: .mastercard,
                kindLabel: "Credit",
            )
            KWCardArt(
                palette: .lima,
                bank: "Bank One",
                badge: .tag("Frozen"),
                holder: "Family",
                lastFour: "5678",
                network: .mastercard,
                kindLabel: "Credit",
                isFrozen: true,
            )
            KWCardArt(palette: .grafito, bank: "Bank Two", badge: .amount("−C$941.30"), showsChip: false)
            KWCardArt(
                palette: .violeta,
                bank: "Bank One",
                badge: .tag("Credit"),
                showsContactless: false,
                lastFour: "1234",
                network: .visa,
                kindLabel: "Debit",
            )
        }
        .padding(KWLayout.gutter)
        assertComponentSnapshot(of: view, height: 1060)
    }

    @Test
    func metallicPalettesPrintInDarkInk() {
        let view = VStack(spacing: KWSpacing.xl) {
            KWCardArt(palette: .platino, bank: "Bank One", holder: "ALEX", lastFour: "4321", network: .visa, kindLabel: "Credit")
            KWCardArt(palette: .oro, bank: "Bank Two", holder: "ALEX", lastFour: "8765", network: .mastercard, kindLabel: "Credit")
            KWCardArt(palette: .rojo, bank: "Bank Three", holder: "ALEX", lastFour: "1005", network: .visa, kindLabel: "Debit")
        }
        .padding(KWLayout.gutter)
        assertComponentSnapshot(of: view, height: 800)
    }

    @Test
    func amexGroupsItsNumberAndPrintsTheBanknote() {
        let view = VStack(spacing: KWSpacing.xl) {
            KWCardArt(palette: .oro, bank: "Bank Three", lastFour: "1005", numberGroups: [4, 6, 5], network: .amex, kindLabel: "Credit")
            KWBanknote(title: "Wallet", amount: "C$8,390", footnote: "≈ $229.08", currency: "NIO")
        }
        .padding(KWLayout.gutter)
        assertComponentSnapshot(of: view, height: 480)
    }
}
