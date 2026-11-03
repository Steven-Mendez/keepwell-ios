import SwiftUI

/// Every stroke icon in the design, drawn from its original 24×24 SVG geometry.
public enum KWIcon: String, CaseIterable, Sendable {
    case addCard
    case arrowDown
    case arrowDownLeft
    case arrowRight
    case arrowUp
    case arrowUpRight
    case bank
    case barsBaseline
    case bolt
    case bus
    case cart
    case cash
    case chartBars
    case check
    case chevronLeft
    case chevronRight
    case clock
    case close
    case cloud
    case contactless
    case creditCard
    case download
    case droplet
    case eye
    case eyeOff
    case faceID
    case freeze
    case health
    case heart
    case home
    case list
    case more
    case moreFilled
    case pencil
    case person
    case personOff
    case phone
    case plus
    case restaurant
    case search
    case settings
    case share
    case subscription
    case tabAccounts
    case tools
    case touchID
    case transfer
    case trash
    case wallet

    enum Element {
        case path(String)
        case circle(cx: CGFloat, cy: CGFloat, radius: CGFloat)
        case rect(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, radius: CGFloat)
    }

    /// The SVG `stroke-linejoin` each icon was drawn with; the rest use the SVG default (miter).
    var roundJoins: Bool {
        switch self {
        case .arrowDown, .arrowDownLeft, .arrowRight, .arrowUp, .arrowUpRight, .bank, .bolt, .bus, .cart, .cash, .check,
             .cloud, .creditCard, .download, .droplet, .faceID, .health, .heart, .home, .pencil, .phone, .settings, .share, .subscription,
             .tools, .transfer, .trash, .wallet:
            true
        default:
            false
        }
    }

    var elements: [Element] {
        switch self {
        case .addCard: [.rect(x: 3, y: 7, width: 14, height: 10, radius: 2), .path("M20 10v6M17 13h6")]
        case .arrowDown: [.path("M12 4v14M6 12l6 6 6-6")]
        case .arrowDownLeft: [.path("M17 7 7 17M16 17H7V8")]
        case .arrowRight: [.path("M5 12h14M13 6l6 6-6 6")]
        case .arrowUp: [.path("M12 19V5M6 11l6-6 6 6")]
        case .arrowUpRight: [.path("M7 17 17 7M8 7h9v9")]
        case .bank: [.path("M3 10 12 4l9 6M5 10v8M19 10v8M9 10v8M15 10v8M3 20h18")]
        case .barsBaseline: [.path("M4 20V10M10 20V4M16 20v-7M22 20H2")]
        case .bolt: [.path("M13 2 4 14h7l-1 8 9-12h-7z")]
        case .bus:
            [
                .rect(x: 4, y: 4, width: 16, height: 13, radius: 3),
                .path("M4 11h16M8 20l-1 1M16 20l1 1M8 14h.01M16 14h.01"),
            ]
        case .cart:
            [.path("M3 4h2l2.4 11h11L21 7H6.2"), .circle(cx: 9, cy: 19, radius: 1.5), .circle(cx: 17, cy: 19, radius: 1.5)]
        case .cash: [.rect(x: 3, y: 6, width: 18, height: 12, radius: 2), .circle(cx: 12, cy: 12, radius: 2.5)]
        case .chartBars: [.path("M6 20V11M12 20V5M18 20v-6")]
        case .check: [.path("M5 12l5 5 9-10")]
        case .chevronLeft: [.path("m15 6-6 6 6 6")]
        case .chevronRight: [.path("m9 6 6 6-6 6")]
        case .clock: [.circle(cx: 12, cy: 12, radius: 9), .path("M12 7v5l3 2")]
        case .close: [.path("M6 6l12 12M18 6 6 18")]
        case .cloud: [.path("M7 18a5 5 0 0 1-.6-10A6 6 0 0 1 18 9a4.5 4.5 0 0 1-.5 9z")]
        case .contactless: [.path("M8.5 8.5a5 5 0 0 1 0 7M12 6a8.5 8.5 0 0 1 0 12M15.5 3.5a12 12 0 0 1 0 17")]
        case .creditCard: [.rect(x: 3, y: 6, width: 18, height: 13, radius: 2), .path("M3 10h18M7 15h4")]
        case .download: [.path("M12 3v12M7 10l5 5 5-5M5 15v4a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2v-4")]
        case .droplet: [.path("M12 21a7 7 0 0 0 7-7c0-2-1-3.9-3-5.5S12.5 4.5 12 2c-.5 2.5-2 4.9-4 6.5S5 12 5 14a7 7 0 0 0 7 7z")]
        case .eye:
            [
                .path("M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7S2 12 2 12z"),
                .circle(cx: 12, cy: 12, radius: 3),
            ]
        case .eyeOff:
            [
                .path("M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7S2 12 2 12z"),
                .circle(cx: 12, cy: 12, radius: 3),
                .path("M3 3l18 18"),
            ]
        case .faceID:
            [.path(
                "M3 8V5a2 2 0 0 1 2-2h3M16 3h3a2 2 0 0 1 2 2v3M21 16v3a2 2 0 0 1-2 2h-3M8 21H5a2 2 0 0 1-2-2v-3"
                    + "M9 9v1M15 9v1M12 9v4h-1M9 16c1.7 1.3 4.3 1.3 6 0",
            )]
        case .freeze: [.path("M12 2v20M4.9 6l14.2 12M4.9 18 19.1 6")]
        case .health: [.path("M12 3v18M3 12h18"), .circle(cx: 12, cy: 12, radius: 9)]
        case .heart: [.path("M12 21s-7-4.4-7-10a4 4 0 0 1 7-2.6A4 4 0 0 1 19 11c0 5.6-7 10-7 10z")]
        case .home: [.path("M3 10.5 12 3l9 7.5V20a1 1 0 0 1-1 1h-5v-6h-6v6H4a1 1 0 0 1-1-1z")]
        case .list: [.path("M8 6h13M8 12h13M8 18h13M3 6h.01M3 12h.01M3 18h.01")]
        case .more: [.path("M5 12h.01M12 12h.01M19 12h.01")]
        case .moreFilled:
            [.circle(cx: 5, cy: 12, radius: 1.5), .circle(cx: 12, cy: 12, radius: 1.5), .circle(cx: 19, cy: 12, radius: 1.5)]
        case .pencil: [.path("M4 20h4L19 9a2.8 2.8 0 0 0-4-4L4 16zM13.5 6.5l4 4")]
        case .person: [.circle(cx: 12, cy: 8, radius: 4), .path("M4 21c1.5-4 4.5-6 8-6s6.5 2 8 6")]
        case .personOff: [.circle(cx: 12, cy: 8, radius: 4), .path("M4 21c1.5-4 4.5-6 8-6s6.5 2 8 6M3 3l18 18")]
        case .phone: [.rect(x: 6, y: 2, width: 12, height: 20, radius: 3), .path("M11 18h2")]
        case .plus: [.path("M12 5v14M5 12h14")]
        case .restaurant: [.path("M6 3v8a2 2 0 0 0 4 0V3M8 11v10M17 3c-2 0-3 2-3 5s1 4 3 4v9")]
        case .search: [.circle(cx: 11, cy: 11, radius: 7), .path("m20 20-3.5-3.5")]
        // A gear rather than the design's rays, which read as a sun (brightness) on iOS.
        case .settings:
            [
                .path(
                    "M12.22 2h-.44a2 2 0 0 0-2 2v.18a2 2 0 0 1-1 1.73l-.43.25a2 2 0 0 1-2 0l-.15-.08a2 2 0 0 0-2.73.73l-.22.38"
                        + "a2 2 0 0 0 .73 2.73l.15.1a2 2 0 0 1 1 1.72v.51a2 2 0 0 1-1 1.74l-.15.09a2 2 0 0 0-.73 2.73l.22.38"
                        + "a2 2 0 0 0 2.73.73l.15-.08a2 2 0 0 1 2 0l.43.25a2 2 0 0 1 1 1.73V20a2 2 0 0 0 2 2h.44a2 2 0 0 0 2-2"
                        + "v-.18a2 2 0 0 1 1-1.73l.43-.25a2 2 0 0 1 2 0l.15.08a2 2 0 0 0 2.73-.73l.22-.39a2 2 0 0 0-.73-2.73"
                        + "l-.15-.08a2 2 0 0 1-1-1.74v-.5a2 2 0 0 1 1-1.74l.15-.09a2 2 0 0 0 .73-2.73l-.22-.38a2 2 0 0 0-2.73-.73"
                        + "l-.15.08a2 2 0 0 1-2 0l-.43-.25a2 2 0 0 1-1-1.73V4a2 2 0 0 0-2-2z",
                ),
                .circle(cx: 12, cy: 12, radius: 3),
            ]
        case .share: [.path("M12 15V3M7 8l5-5 5 5M5 13v6a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2v-6")]
        case .subscription: [.path("M17 2l3 3-3 3M4 11V9a4 4 0 0 1 4-4h12M7 22l-3-3 3-3M20 13v2a4 4 0 0 1-4 4H4")]
        case .tabAccounts: [.rect(x: 3, y: 6, width: 18, height: 14, radius: 2), .path("M3 10h18M16 15h2")]
        case .tools: [.path("M14.7 6.3a4 4 0 0 0-5.4 5.4L3 18l3 3 6.3-6.3a4 4 0 0 0 5.4-5.4l-2.5 2.5-2.4-.6-.6-2.4z")]
        case .touchID:
            [.path(
                "M6.5 6.5A8 8 0 0 1 19.6 9M4.3 10.5A8 8 0 0 0 4 13M8 20c-.8-1.6-1.2-3.4-1.2-5.2a5.2 5.2 0 0 1 10.4 0"
                    + "M12 14.5v1.2c0 2 .5 3.9 1.4 5.6M9.4 14.6a2.6 2.6 0 0 1 5.2 0v.6c0 1.6.3 3.1.9 4.5M17.2 18.6c.3-1 .4-2 .4-3",
            )]
        case .transfer: [.path("M4 8h14l-3-3M20 16H6l3 3")]
        case .trash: [.path("M3 6h18M8 6V4h8v2M19 6l-1 14H6L5 6M10 11v6M14 11v6")]
        case .wallet:
            [
                .rect(x: 3, y: 6, width: 18, height: 12, radius: 2),
                .circle(cx: 12, cy: 12, radius: 2.5),
                .path("M6 9v.01M18 15v.01"),
            ]
        }
    }

    /// The icon in its 24×24 design coordinate space.
    var path: Path {
        var combined = Path()
        for element in elements {
            switch element {
            case let .path(data):
                combined.addPath(SVGPath.path(from: data))
            case let .circle(cx, cy, radius):
                combined.addEllipse(in: CGRect(x: cx - radius, y: cy - radius, width: 2 * radius, height: 2 * radius))
            case let .rect(x, y, width, height, radius):
                combined.addRoundedRect(
                    in: CGRect(x: x, y: y, width: width, height: height),
                    cornerSize: CGSize(width: radius, height: radius),
                )
            }
        }
        return combined
    }
}
