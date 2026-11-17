import Foundation
import SharedPresentation

extension AppContainer {
    /// UI tests never reach the network, so their screens show monograms.
    static func makeBrandLogos(environment: AppEnvironment = .current) -> (any BrandLogoProviding)? {
        guard environment.brandLogos.isActive, !environment.isUITesting else { return nil }
        // The shared session keeps the system's HTTP cache and nothing of our own.
        return BrandfetchLogos(configuration: environment.brandLogos) { request in
            try await URLSession.shared.data(for: request)
        }
    }

    /// Brandfetch's brand search for the "Business" and "Via" pickers, on the same switch and client id
    /// as the logos; UI tests never reach it.
    static func makeBrandSearch(environment: AppEnvironment = .current) -> (any BrandSearching)? {
        guard environment.brandLogos.isActive, !environment.isUITesting else { return nil }
        return BrandfetchSearch(configuration: environment.brandLogos) { request in
            try await URLSession.shared.data(for: request)
        }
    }
}
