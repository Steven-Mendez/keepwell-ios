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
            bank: "Banco Uno",
            badge: .amount("−C$197.02 · −$16.79"),
            caption: "Crédito · 2 plásticos",
            lastFour: "1234",
            network: "mastercard",
        )
        assertComponentSnapshot(of: card.padding(KWLayout.gutter), height: 290)
    }

    @Test
    func paletteAndStateVariants() {
        let view = VStack(spacing: KWSpacing.xl) {
            KWCardArt(
                palette: .lima,
                bank: "Banco Uno",
                badge: .tag("Adicional"),
                caption: "Familiar",
                lastFour: "5678",
                network: "mastercard",
            )
            KWCardArt(
                palette: .lima,
                bank: "Banco Uno",
                badge: .tag("Congelada"),
                caption: "Familiar",
                lastFour: "5678",
                network: "mastercard",
                isFrozen: true,
            )
            KWCardArt(palette: .grafito, bank: "Banco Dos", badge: .amount("−C$941.30"), showsChip: false)
            KWCardArt(
                palette: .violeta,
                bank: "Banco Uno",
                badge: .tag("Crédito"),
                showsContactless: false,
                lastFour: "1234",
                network: "VISA",
            )
        }
        .padding(KWLayout.gutter)
        assertComponentSnapshot(of: view, height: 1060)
    }
}
