import Testing
@testable import DesignSystem

@Suite("Fonts")
struct FontsTests {
    /// Fails if a bundled Inter file goes missing, which would silently fall back to the system font.
    @Test
    func interFontsRegister() {
        #expect(KWFonts.register())
    }
}
