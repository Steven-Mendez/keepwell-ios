import Foundation

extension OnboardingViewModel {
    // MARK: Done summary

    /// "All set, Steven" once there's a name to say.
    public var doneTitle: String {
        guard let name = preferredName else { return String(localized: "All set", bundle: #bundle) }
        return String(localized: "All set, \(name)", bundle: #bundle)
    }

    public var currenciesSummary: String {
        [principal, second].compactMap(\.self).joined(separator: " + ")
    }

    public var rateSummary: String? {
        guard let second, let rate else { return nil }
        return "1 \(principal) = \(rate) \(second)"
    }
}
