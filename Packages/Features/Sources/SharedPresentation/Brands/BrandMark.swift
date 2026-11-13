import DesignSystem
import Domain
import SwiftUI

/// A known brand's mark in the row's badge: the monogram (its initial on the category's color)
/// paints at once, and Brandfetch's logo covers it once loaded. If the logo fails the monogram
/// stays: no gap, no broken image, and no jump, since both share one neutral circle.
public struct BrandMark: View {
    private let brand: LogoSubject
    private let tint: Color
    private let diameter: CGFloat
    @Environment(\.brandLogos) private var logos
    @Environment(\.colorScheme) private var colorScheme
    @State private var logo: (key: String, image: UIImage)?

    public init(_ brand: Brand, tint: Color, diameter: CGFloat = 40) {
        self.init(LogoSubject(brand), tint: tint, diameter: diameter)
    }

    /// A brand of the table or a merchant: the name its monogram comes from and the domain of its logo.
    public init(_ subject: LogoSubject, tint: Color, diameter: CGFloat = 40) {
        brand = subject
        self.tint = tint
        self.diameter = diameter
    }

    private var key: String {
        "\(brand.domain)/\(BrandLogoTheme(colorScheme).rawValue)"
    }

    public var body: some View {
        ZStack {
            Text(brand.monogram)
                .font(.kw(diameter * 0.4, weight: 700))
                .foregroundStyle(tint)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(tint.opacity(0.16))
            if let logo, logo.key == key {
                Image(uiImage: logo.image)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            }
        }
        .frame(width: diameter, height: diameter)
        .background(KWColor.Surface.surface2)
        .clipShape(Circle())
        .accessibilityHidden(true)
        .task(id: key) {
            guard let logos else { return }
            let key = key
            guard let image = await logos.logo(for: brand.domain, theme: BrandLogoTheme(colorScheme)) else { return }
            withAnimation(.easeOut(duration: 0.2)) { logo = (key, image) }
        }
    }
}

/// A rule's or movement's leading badge: its merchant's logo when given (`logo`), else the brand its
/// text names, when the table knows one, else the given fallback. Only a domain is ever requested;
/// the text never leaves.
public struct BrandOrFallbackIcon<Fallback: View>: View {
    private let brand: LogoSubject?
    private let tint: Color
    private let diameter: CGFloat
    private let fallback: Fallback

    public init(
        text: String,
        logo: LogoSubject? = nil,
        tint: Color,
        diameter: CGFloat = 40,
        @ViewBuilder fallback: () -> Fallback,
    ) {
        brand = logo ?? BrandCatalog.brand(for: text).map(LogoSubject.init)
        self.tint = tint
        self.diameter = diameter
        self.fallback = fallback()
    }

    public var body: some View {
        if let brand {
            BrandMark(brand, tint: tint, diameter: diameter)
        } else {
            fallback
        }
    }
}

#Preview {
    VStack(spacing: KWSpacing.md) {
        ForEach(["Spotify", "Netflix", "Claro", "Uber Eats"], id: \.self) { name in
            BrandOrFallbackIcon(text: name, tint: KWColor.Brand.link) { EmptyView() }
        }
    }
    .padding()
    .background(KWColor.Surface.bg)
}
