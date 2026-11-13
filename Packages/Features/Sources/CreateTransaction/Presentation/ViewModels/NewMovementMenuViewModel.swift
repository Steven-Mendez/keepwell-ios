import CreateTransactionDomain
import Foundation
import Observation

/// The "What are you recording?" sheet: only the types the person's accounts can record.
@MainActor
@Observable
public final class NewMovementMenuViewModel {
    public struct Option: Identifiable, Hashable, Sendable {
        public let type: MovementType
        public let title: String
        public let subtitle: String
        public var id: MovementType { type }
    }

    public private(set) var options: [Option] = []
    private let getContext: any GetTransactionContextUseCase

    public init(getContext: any GetTransactionContextUseCase) {
        self.getContext = getContext
    }

    public func load() async {
        let accounts = await (try? getContext.execute())?.accounts.open ?? []
        // Without accounts yet, expenses still open the flow, which explains what is missing.
        let types = accounts.isEmpty ? [.expense, .income] : MovementType.available(with: accounts)
        options = types.map { Option(type: $0, title: CreateTransactionViewModel.title(of: $0), subtitle: Self.subtitle(of: $0)) }
    }

    static func subtitle(of type: MovementType) -> String {
        switch type {
        case .expense: String(localized: "A purchase, a bill, a subscription", bundle: #bundle)
        case .income: String(localized: "Salary, a refund, money you received", bundle: #bundle)
        case .transfer: String(localized: "Move money between your accounts and cash", bundle: #bundle)
        case .withdrawal: String(localized: "Take cash out of a bank account", bundle: #bundle)
        case .cardPayment: String(localized: "Pay what you owe on a credit card", bundle: #bundle)
        }
    }
}
