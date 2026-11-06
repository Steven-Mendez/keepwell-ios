import Domain
import Foundation
import Observation
import SettingsDomain
import SharedPresentation

/// Settings › Payment methods: what each account can pay with, and how each card is doing.
@MainActor
@Observable
public final class PaymentMethodsViewModel {
    public private(set) var groups: [PaymentMethodGroup] = []
    public private(set) var hasFailed = false

    private let getMethods: any GetPaymentMethodsUseCase
    private let now: @Sendable () -> Date
    private let calendar: Calendar

    public init(
        getMethods: any GetPaymentMethodsUseCase,
        now: @escaping @Sendable () -> Date = { .now },
        calendar: Calendar = .current,
    ) {
        self.getMethods = getMethods
        self.now = now
        self.calendar = calendar
    }

    public func load() async {
        do {
            groups = try await getMethods.execute()
            hasFailed = false
        } catch {
            hasFailed = true
        }
    }

    // MARK: - Display

    func title(of group: PaymentMethodGroup) -> String {
        CardDisplay.name(of: group.account)
    }

    func title(of card: Card, in group: PaymentMethodGroup) -> String {
        switch card.kind {
        case .transfer: String(localized: "Bank transfer", bundle: #bundle)
        case .debit, .creditHolder: [card.productName, CardDisplay.methodTitle(card, account: group.account)]
            .compactMap(\.self)
            .joined(separator: " · ")
        }
    }

    /// "Credit · valid thru 09/28", warning when it's expired or expires this month.
    func subtitle(of card: Card) -> (text: String, isWarning: Bool) {
        let kind = switch card.kind {
        case .debit: String(localized: "Debit", bundle: #bundle)
        case .creditHolder: String(localized: "Credit", bundle: #bundle)
        case .transfer: String(localized: "Charged straight to the account", bundle: #bundle)
        }
        guard let expiry = card.expiry else { return (kind, false) }
        let parts = calendar.dateComponents([.year, .month], from: now())
        let today = (parts.year ?? 0, parts.month ?? 0)
        let printed = CardDisplay.expiry(expiry)
        if (expiry.year, expiry.month) < today {
            return (String(localized: "\(kind) · expired \(printed)", bundle: #bundle), true)
        }
        if (expiry.year, expiry.month) == today {
            return (String(localized: "\(kind) · expires this month", bundle: #bundle), true)
        }
        return (String(localized: "\(kind) · valid thru \(printed)", bundle: #bundle), false)
    }

    /// Plastics open their card's screen; the transfer channel has none of its own.
    func opensScreen(_ card: Card) -> Bool {
        card.kind != .transfer
    }
}
