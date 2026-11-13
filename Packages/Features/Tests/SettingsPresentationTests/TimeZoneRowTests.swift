import Foundation
import Testing
@testable import SettingsPresentation

/// What the Time zone row says under its title: the saved zone, or the iPhone's while none is.
@Suite("Time zone row")
@MainActor
struct TimeZoneRowTests {
    private let lima = TimeZone(identifier: "America/Lima") ?? .gmt

    @Test
    func showsTheSavedZone() {
        #expect(TimeZoneRow.summary(saved: "America/Argentina/Buenos_Aires", device: lima) == "America/Argentina/Buenos Aires")
    }

    @Test
    func withoutOneSaysItIsTheIPhones() {
        #expect(TimeZoneRow.summary(saved: nil, device: lima) == "America/Lima · From this iPhone")
    }
}
