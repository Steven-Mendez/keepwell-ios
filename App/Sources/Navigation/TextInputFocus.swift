import UIKit

/// Whether a text field or text view owns the keyboard. The shortcut keys (N, E, 1…) must not fire
/// while someone types, and SwiftUI's key handlers also see keys that a focused field is about to
/// take, so this asks UIKit who the first responder is.
@MainActor
enum TextInputFocus {
    private weak static var responder: UIResponder?

    static var isEditing: Bool {
        responder = nil
        // With no target, the action travels the responder chain from the first responder.
        UIApplication.shared.sendAction(#selector(UIResponder.keepwellCaptureFirstResponder), to: nil, from: nil, for: nil)
        return responder is UITextInput
    }

    fileprivate static func capture(_ candidate: UIResponder) {
        responder = candidate
    }
}

extension UIResponder {
    @objc
    fileprivate func keepwellCaptureFirstResponder() {
        TextInputFocus.capture(self)
    }
}
