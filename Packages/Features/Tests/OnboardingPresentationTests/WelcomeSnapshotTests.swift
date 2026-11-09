import FeatureTestSupport
import SwiftUI
import Testing
@testable import OnboardingPresentation

@Suite("Splash and welcome snapshots")
@MainActor
struct WelcomeSnapshotTests {
    @Test
    func splash() {
        assertScreenSnapshot(of: SplashView())
    }

    @Test
    func welcome() {
        assertScreenSnapshot(of: WelcomeView(onStart: {}))
    }

    @Test
    func returning() {
        assertScreenSnapshot(of: ReturningView(
            restoreState: .idle, onBack: {}, onRestoreFromAccount: {}, onRestoreFromFile: {}, onStartFresh: {},
        ))
    }

    @Test
    func returningAfterFailedRestore() {
        assertScreenSnapshot(of: ReturningView(
            restoreState: .notFound, onBack: {}, onRestoreFromAccount: {}, onRestoreFromFile: {}, onStartFresh: {},
        ))
    }
}
