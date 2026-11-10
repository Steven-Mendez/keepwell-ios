import SwiftUI
import UIKit

/// Shows the lock screen or the privacy cover in a window above everything, sheets and full-screen
/// flows included. An overlay inside the root view sits under presented flows, which would leave
/// a half-entered movement visible while the app is locked.
@MainActor
final class CoverWindow {
    private var window: UIWindow?

    func show(_ content: some View) {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        let host = UIHostingController(rootView: AnyView(content))
        host.view.backgroundColor = .clear
        let window = window ?? UIWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        window.rootViewController = host
        window.isHidden = false
        self.window = window
    }

    func hide() {
        window?.isHidden = true
        window?.rootViewController = nil
        window = nil
    }
}
