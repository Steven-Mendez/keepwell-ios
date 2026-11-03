import CoreText
import Foundation
import OSLog

/// Registers the Inter family bundled with this package (OFL license, see `Inter-LICENSE.txt`).
public enum KWFonts {
    public enum Weight: String, CaseIterable, Sendable {
        case regular = "Inter-Regular"
        case medium = "Inter-Medium"
        case semibold = "Inter-SemiBold"
        case bold = "Inter-Bold"
        case extraBold = "Inter-ExtraBold"

        /// Accepts CSS numeric weights (400…800), the unit design specs use.
        public init(cssWeight: Int) {
            switch cssWeight {
            case ..<500: self = .regular
            case 500 ..< 600: self = .medium
            case 600 ..< 700: self = .semibold
            case 700 ..< 800: self = .bold
            default: self = .extraBold
            }
        }

        public var postScriptName: String { rawValue }
    }

    private static let logger = Logger(subsystem: "DesignSystem", category: "Fonts")

    /// Evaluated exactly once (lazy, thread-safe static initialization).
    private static let registration: Bool = {
        var allRegistered = true
        for weight in Weight.allCases {
            guard let url = Bundle.module.url(forResource: weight.rawValue, withExtension: "ttf") else {
                logger.error("Font not found in bundle: \(weight.rawValue, privacy: .public)")
                allRegistered = false
                continue
            }
            var error: Unmanaged<CFError>?
            if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
                // Already being registered is not a real error.
                let cfError = error?.takeRetainedValue()
                let code = cfError.map { CFErrorGetCode($0) } ?? 0
                if code != CTFontManagerError.alreadyRegistered.rawValue {
                    logger.error("Could not register \(weight.rawValue, privacy: .public): \(code)")
                    allRegistered = false
                }
            }
        }
        return allRegistered
    }()

    /// Registers Inter for the current process. Idempotent; call it at app and widget startup.
    @discardableResult
    public static func register() -> Bool {
        registration
    }
}
