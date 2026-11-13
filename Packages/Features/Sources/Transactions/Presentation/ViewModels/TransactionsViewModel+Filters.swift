import Core
import Domain
import Foundation
import TransactionsDomain

/// What the "Filters" sheet edits before "Apply": the amount bounds as typed and the origin.
public struct MoreFiltersDraft: Equatable {
    public var minText: String
    public var maxText: String
    public var origin: TransactionOrigin

    public init(minText: String = "", maxText: String = "", origin: TransactionOrigin = .any) {
        self.minText = minText
        self.maxText = maxText
        self.origin = origin
    }

    /// A typed bound: `nil` when blank, `.failure` when it isn't an amount.
    private static func bound(_ text: String) -> Result<Decimal?, AmountInputError> {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return .success(nil) }
        guard let value = AmountInput.decimal(from: text) else { return .failure(AmountInputError()) }
        return .success(value)
    }

    struct AmountInputError: Error {}

    /// The range typed; `nil` while a bound isn't an amount.
    public var range: AmountRange? {
        guard case let .success(min) = Self.bound(minText), case let .success(max) = Self.bound(maxText) else { return nil }
        return AmountRange(min: min, max: max)
    }

    /// "Minimum is above maximum" shows and "Apply" stays off.
    public var isMinAboveMax: Bool {
        range?.problem == .minAboveMax
    }

    public var canApply: Bool {
        range != nil && !isMinAboveMax
    }
}

/// An active amount or origin filter, shown as a filled chip above the list.
public struct ActiveFilterChip: Identifiable, Equatable {
    public enum Kind: Hashable, Sendable { case amount, origin }
    public let kind: Kind
    public let title: String
    public var id: Kind { kind }
}

extension TransactionsViewModel {
    /// What the amount and origin filters read.
    var queryContext: TransactionQueryContext? {
        list.map { TransactionQueryContext(principal: $0.settings.principal, rules: $0.recurringRules) }
    }

    /// The principal currency the amount range is read in.
    var principalCurrency: String {
        list?.settings.principal ?? "USD"
    }

    /// "Converted to C$ at each movement's rate" only matters when there is a second currency.
    var conversionNote: String? {
        guard let settings = list?.settings, settings.second != nil else { return nil }
        return String(localized: "Converted to \(settings.principal) at each movement's rate", bundle: #bundle)
    }

    /// The amount chip ("≥ C$100", "≤ C$500", "C$100 – 500"), then the origin one ("Subscriptions",
    /// the rule's name, or "Deleted rule"). Empty without either filter.
    public var activeFilters: [ActiveFilterChip] {
        [amountTitle.map { ActiveFilterChip(kind: .amount, title: $0) }, originTitle.map { ActiveFilterChip(kind: .origin, title: $0) }]
            .compactMap(\.self)
    }

    /// The ✕ of an active chip.
    public func clear(_ kind: ActiveFilterChip.Kind) {
        switch kind {
        case .amount: amount = AmountRange()
        case .origin: origin = .any
        }
    }

    /// The sheet opens on what's applied.
    public func makeFiltersDraft() -> MoreFiltersDraft {
        MoreFiltersDraft(
            minText: amount.min.map { formatter.number($0) } ?? "",
            maxText: amount.max.map { formatter.number($0) } ?? "",
            origin: origin,
        )
    }

    /// "Apply": does nothing while the draft can't be applied.
    public func apply(_ draft: MoreFiltersDraft) {
        guard draft.canApply, let range = draft.range else { return }
        amount = range
        origin = draft.origin
    }

    private var amountTitle: String? {
        let currency = principalCurrency
        switch (amount.min, amount.max) {
        case let (min?, max?): return "\(bound(min, currency: currency)) – \(bound(max, currency: nil))"
        case let (min?, nil): return "≥ \(bound(min, currency: currency))"
        case let (nil, max?): return "≤ \(bound(max, currency: currency))"
        case (nil, nil): return nil
        }
    }

    /// Whole amounts without cents ("C$100"), others with them ("C$99.50").
    private func bound(_ value: Decimal, currency: String?) -> String {
        let digits = value.rounded(scale: 0) == value ? 0 : 2
        guard let currency else { return formatter.number(value, fractionDigits: digits) }
        return formatter.string(from: value, currencyCode: currency, fractionDigits: digits)
    }

    private var originTitle: String? {
        switch origin {
        case .any:
            nil
        case .subscriptions:
            String(localized: "Subscriptions", bundle: #bundle)
        case let .rule(id):
            list?.recurringRules.first { $0.id == id }?.name ?? String(localized: "Deleted rule", bundle: #bundle)
        }
    }
}
