import CoreGraphics
import Foundation

/// An SVG elliptical arc in endpoint form, converted to cubic Béziers because SwiftUI's `Path`
/// only offers center-form circular arcs. Follows the SVG 1.1 implementation notes (F.6.5).
struct SVGArc {
    struct Cubic: Equatable {
        let control1: CGPoint
        let control2: CGPoint
        let end: CGPoint
    }

    var start: CGPoint
    var end: CGPoint
    var radii: CGSize
    var rotation: CGFloat = 0
    var largeArc = false
    var sweep = true

    private struct Ellipse {
        let center: CGPoint
        let radiusX: CGFloat
        let radiusY: CGFloat
        let cosPhi: CGFloat
        let sinPhi: CGFloat

        func point(at theta: CGFloat) -> CGPoint {
            CGPoint(
                x: center.x + radiusX * cos(theta) * cosPhi - radiusY * sin(theta) * sinPhi,
                y: center.y + radiusX * cos(theta) * sinPhi + radiusY * sin(theta) * cosPhi,
            )
        }

        func derivative(at theta: CGFloat) -> CGPoint {
            CGPoint(
                x: -radiusX * sin(theta) * cosPhi - radiusY * cos(theta) * sinPhi,
                y: -radiusX * sin(theta) * sinPhi + radiusY * cos(theta) * cosPhi,
            )
        }
    }

    func cubics() -> [Cubic] {
        guard start != end else { return [] }
        guard radii.width > 0, radii.height > 0 else {
            return [Cubic(control1: start, control2: end, end: end)]
        }
        let (ellipse, startAngle, delta) = centerParameterization()

        // Segments of at most 90° keep the cubic approximation error invisible at icon sizes.
        let segments = max(1, Int(ceil(abs(delta) / (.pi / 2))))
        let step = delta / CGFloat(segments)
        let kappa = 4 / 3 * tan(step / 4)

        return (0 ..< segments).map { segment in
            let theta = startAngle + CGFloat(segment) * step
            let from = ellipse.point(at: theta)
            let to = segment == segments - 1 ? end : ellipse.point(at: theta + step)
            let d1 = ellipse.derivative(at: theta)
            let d2 = ellipse.derivative(at: theta + step)
            return Cubic(
                control1: CGPoint(x: from.x + kappa * d1.x, y: from.y + kappa * d1.y),
                control2: CGPoint(x: to.x - kappa * d2.x, y: to.y - kappa * d2.y),
                end: to,
            )
        }
    }

    private func centerParameterization() -> (Ellipse, startAngle: CGFloat, delta: CGFloat) {
        let cosPhi = cos(rotation)
        let sinPhi = sin(rotation)
        let halfDX = (start.x - end.x) / 2
        let halfDY = (start.y - end.y) / 2
        let x1p = cosPhi * halfDX + sinPhi * halfDY
        let y1p = -sinPhi * halfDX + cosPhi * halfDY

        // Radii too small to reach the endpoint are scaled up, as the spec requires.
        var radiusX = radii.width
        var radiusY = radii.height
        let lambda = (x1p * x1p) / (radiusX * radiusX) + (y1p * y1p) / (radiusY * radiusY)
        if lambda > 1 {
            radiusX *= sqrt(lambda)
            radiusY *= sqrt(lambda)
        }

        let rx2 = radiusX * radiusX
        let ry2 = radiusY * radiusY
        let numerator = rx2 * ry2 - rx2 * y1p * y1p - ry2 * x1p * x1p
        let denominator = rx2 * y1p * y1p + ry2 * x1p * x1p
        let magnitude = sqrt(max(0, numerator / denominator))
        let factor = largeArc == sweep ? -magnitude : magnitude
        let cxp = factor * radiusX * y1p / radiusY
        let cyp = -factor * radiusY * x1p / radiusX

        let center = CGPoint(
            x: cosPhi * cxp - sinPhi * cyp + (start.x + end.x) / 2,
            y: sinPhi * cxp + cosPhi * cyp + (start.y + end.y) / 2,
        )
        let startAngle = Self.angle(1, 0, (x1p - cxp) / radiusX, (y1p - cyp) / radiusY)
        var delta = Self.angle(
            (x1p - cxp) / radiusX, (y1p - cyp) / radiusY,
            (-x1p - cxp) / radiusX, (-y1p - cyp) / radiusY,
        )
        if !sweep, delta > 0 {
            delta -= 2 * .pi
        } else if sweep, delta < 0 {
            delta += 2 * .pi
        }
        let ellipse = Ellipse(center: center, radiusX: radiusX, radiusY: radiusY, cosPhi: cosPhi, sinPhi: sinPhi)
        return (ellipse, startAngle, delta)
    }

    private static func angle(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
        atan2(ux * vy - uy * vx, ux * vx + uy * vy)
    }
}
