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
            network: "mastercard",
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
                caption: "Family",
                lastFour: "5678",
                network: "mastercard",
            )
            KWCardArt(
                palette: .lima,
                bank: "Bank One",
                badge: .tag("Frozen"),
                caption: "Family",
                lastFour: "5678",
                network: "mastercard",
                isFrozen: true,
            )
            KWCardArt(palette: .grafito, bank: "Bank Two", badge: .amount("−C$941.30"), showsChip: false)
            KWCardArt(
                palette: .violeta,
                bank: "Bank One",
                badge: .tag("Credit"),
                showsContactless: false,
                lastFour: "1234",
                network: "VISA",
            )
        }
        .padding(KWLayout.gutter)
        assertComponentSnapshot(of: view, height: 1060)
    }
}
