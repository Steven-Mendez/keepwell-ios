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
}
