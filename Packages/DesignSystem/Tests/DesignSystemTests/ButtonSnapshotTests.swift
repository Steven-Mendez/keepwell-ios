import SwiftUI
import Testing
@testable import DesignSystem

@Suite("Button snapshots")
@MainActor
struct ButtonSnapshotTests {
    @Test
    func variantsAndSizes() {
        let view = VStack(spacing: KWSpacing.sm) {
            Button("Continuar") {}.buttonStyle(.kw())
            Button("Retiro de cajero") {}.buttonStyle(.kw(.secondary))
            Button("Anotar otro") {}.buttonStyle(.kw(.surface, size: .regular))
            Button("Quitar adicional") {}.buttonStyle(.kw(.destructive, size: .row))
            Button("Completar datos de la tarjeta") {}.buttonStyle(.kw(.link, size: .medium))
            Button("Ahora no") {}.buttonStyle(.kw(.plain, size: .text))
            HStack {
                Button("Respaldar ahora") {}.buttonStyle(.kw(.primary, size: .small))
                Button("Restaurar") {}.buttonStyle(.kw(.secondary, size: .small))
                Button("Confirmar") {}.buttonStyle(.kw(.primary, size: .mini))
            }
            Button("Desactivado") {}.buttonStyle(.kw()).disabled(true)
        }
        .padding(KWLayout.gutter)
        assertComponentSnapshot(of: view, height: 560)
    }
}
