import Foundation
import SwiftUI

/// Parses the subset of SVG path data the design's icons use (M L H V C S A Z, absolute and
/// relative, with implicit repeats) so icons render from the exact design geometry instead of
/// hand-approximated shapes.
enum SVGPath {
    static func path(from data: String) -> Path {
        var parser = Parser(tokens: tokenize(data))
        return parser.run()
    }

    enum Token: Equatable {
        case command(Character)
        case number(CGFloat)
    }

    static func tokenize(_ data: String) -> [Token] {
        var tokens: [Token] = []
        var number = ""
        var hasDot = false
        var lastWasExponent = false

        func flush() {
            if let value = Double(number) {
                tokens.append(.number(CGFloat(value)))
            }
            number = ""
            hasDot = false
        }

        for char in data {
            if char.isLetter, char != "e", char != "E" {
                flush()
                tokens.append(.command(char))
            } else if char == "-" || char == "+" {
                // A sign starts a new number unless it belongs to an exponent ("1e-3").
                if !lastWasExponent {
                    flush()
                }
                number.append(char)
            } else if char == "." {
                // "1.5.5" is two numbers: a second dot starts a new one.
                if hasDot {
                    flush()
                }
                number.append(char)
                hasDot = true
            } else if char.isNumber || char == "e" || char == "E" {
                number.append(char)
            } else {
                flush()
            }
            lastWasExponent = char == "e" || char == "E"
        }
        flush()
        return tokens
    }

    private struct Parser {
        let tokens: [Token]
        var index = 0
        var path = Path()
        var current = CGPoint.zero
        var subpathStart = CGPoint.zero
        var lastControl: CGPoint?

        init(tokens: [Token]) {
            self.tokens = tokens
        }

        mutating func run() -> Path {
            var command: Character = "M"
            while index < tokens.count {
                if case let .command(next) = tokens[index] {
                    command = next
                    index += 1
                    if command == "Z" || command == "z" {
                        path.closeSubpath()
                        current = subpathStart
                        lastControl = nil
                        continue
                    }
                }
                guard hasNumber else { break }
                apply(command)
                // After a moveto, implicit repeats are linetos (SVG spec).
                if command == "M" {
                    command = "L"
                }
                if command == "m" {
                    command = "l"
                }
            }
            return path
        }

        private var hasNumber: Bool {
            guard index < tokens.count, case .number = tokens[index] else { return false }
            return true
        }

        private mutating func number() -> CGFloat {
            guard index < tokens.count, case let .number(value) = tokens[index] else { return 0 }
            index += 1
            return value
        }

        private mutating func point(relative: Bool) -> CGPoint {
            let x = number()
            let y = number()
            return relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
        }

        private mutating func apply(_ command: Character) {
            let relative = command.isLowercase
            switch command.uppercased() {
            case "M":
                current = point(relative: relative)
                subpathStart = current
                path.move(to: current)
                lastControl = nil
            case "L":
                current = point(relative: relative)
                path.addLine(to: current)
                lastControl = nil
            case "H":
                let x = number()
                current = CGPoint(x: relative ? current.x + x : x, y: current.y)
                path.addLine(to: current)
                lastControl = nil
            case "V":
                let y = number()
                current = CGPoint(x: current.x, y: relative ? current.y + y : y)
                path.addLine(to: current)
                lastControl = nil
            case "C":
                let control1 = point(relative: relative)
                let control2 = point(relative: relative)
                let end = point(relative: relative)
                addCurve(control1, control2, end)
            case "S":
                let control1 = reflectedControl
                let control2 = point(relative: relative)
                let end = point(relative: relative)
                addCurve(control1, control2, end)
            case "A":
                addArc(relative: relative)
            default:
                index += 1
            }
        }

        private var reflectedControl: CGPoint {
            guard let lastControl else { return current }
            return CGPoint(x: 2 * current.x - lastControl.x, y: 2 * current.y - lastControl.y)
        }

        private mutating func addCurve(_ control1: CGPoint, _ control2: CGPoint, _ end: CGPoint) {
            path.addCurve(to: end, control1: control1, control2: control2)
            lastControl = control2
            current = end
        }

        private mutating func addArc(relative: Bool) {
            let radiusX = abs(number())
            let radiusY = abs(number())
            let rotation = number() * .pi / 180
            let largeArc = number() != 0
            let sweep = number() != 0
            let end = point(relative: relative)
            let arc = SVGArc(
                start: current,
                end: end,
                radii: CGSize(width: radiusX, height: radiusY),
                rotation: rotation,
                largeArc: largeArc,
                sweep: sweep,
            )
            for curve in arc.cubics() {
                path.addCurve(to: curve.end, control1: curve.control1, control2: curve.control2)
            }
            current = end
            lastControl = nil
        }
    }
}
