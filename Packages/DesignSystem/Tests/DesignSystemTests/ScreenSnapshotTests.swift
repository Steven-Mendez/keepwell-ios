import SwiftUI
import Testing
@testable import DesignSystem

@Suite("Screen snapshots")
@MainActor
struct ScreenSnapshotTests {
    @Test
    func screenPadsFromTheDesignTop() {
        let view = KWScreen {
            Text("Contenido").font(KWTextStyle.heading.font)
        }
        assertComponentSnapshot(of: view, height: 140)
    }
}
