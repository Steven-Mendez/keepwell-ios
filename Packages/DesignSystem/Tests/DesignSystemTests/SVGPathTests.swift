import SwiftUI
import Testing
@testable import DesignSystem

@Suite("SVG path parsing")
struct SVGPathTests {
    @Test
    func tokenizesCompactNumbers() {
        #expect(SVGPath.tokenize("M6.4 8-.6-10h.01") == [
            .command("M"), .number(6.4), .number(8), .number(-0.6), .number(-10),
            .command("h"), .number(0.01),
        ])
    }

    @Test
    func secondDotStartsANewNumber() {
        #expect(SVGPath.tokenize("c0 2 .5 3.9 1.4 5.6") == [
            .command("c"), .number(0), .number(2), .number(0.5), .number(3.9), .number(1.4), .number(5.6),
        ])
    }

    @Test
    func relativeMoveRepeatsAsLines() {
        let bounds = SVGPath.path(from: "m15 6-6 6 6 6").boundingRect
        #expect(bounds == CGRect(x: 9, y: 6, width: 6, height: 12))
    }

    @Test
    func horizontalAndVerticalLines() {
        let bounds = SVGPath.path(from: "M3 10h18V20").boundingRect
        #expect(bounds == CGRect(x: 3, y: 10, width: 18, height: 10))
    }

    @Test
    func halfCircleArcReachesItsExtremes() {
        // From (2,12) to (22,12) with r=10 sweeping clockwise passes through the top point (12,2).
        let bounds = SVGPath.path(from: "M2 12A10 10 0 0 1 22 12").boundingRect
        #expect(abs(bounds.minY - 2) < 0.01)
        #expect(abs(bounds.minX - 2) < 0.01)
        #expect(abs(bounds.maxX - 22) < 0.01)
    }

    @Test
    func undersizedArcRadiiAreScaledUp() {
        let curves = SVGArc(start: .zero, end: CGPoint(x: 10, y: 0), radii: CGSize(width: 1, height: 1)).cubics()
        #expect(curves.last?.end == CGPoint(x: 10, y: 0))
        #expect(!curves.isEmpty)
    }

    @Test
    func smoothCurveReflectsPreviousControlPoint() {
        let bounds = SVGPath.path(from: "M0 0C0 10 10 10 10 0S20 -10 20 0").boundingRect
        #expect(bounds.minY < 0)
        #expect(bounds.maxY > 0)
    }

    @Test
    func closePathReturnsToSubpathStart() {
        let path = SVGPath.path(from: "M2 2h4v4z")
        #expect(path.boundingRect == CGRect(x: 2, y: 2, width: 4, height: 4))
    }
}
