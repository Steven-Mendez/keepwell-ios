import Core
import DesignSystem
import Domain
import OnboardingDomain
import SwiftUI

/// Sheet to add or edit one onboarding account. Built from the add-card form patterns (grouped
/// rows with trailing inputs, chips, debt mode cards) since the design has no separate screen.
struct AccountFormView: View {
    enum Field: Hashable {
        case bank
        case name
        case lastFour
        case balance
        case secondBalance
    }

    @State private var draft: OnboardingAccountDraft
    @State private var balanceText: String
    @State private var secondBalanceText: String
    @FocusState private var focus: Field?
    let principal: String
    let second: String?
    let isNew: Bool
    let onSave: (OnboardingAccountDraft) -> Void
    let onRemove: () -> Void
    let onClose: () -> Void

    init(
        draft: OnboardingAccountDraft,
        principal: String,
        second: String?,
        isNew: Bool,
        onSave: @escaping (OnboardingAccountDraft) -> Void,
        onRemove: @escaping () -> Void,
        onClose: @escaping () -> Void,
    ) {
        _draft = State(initialValue: draft)
        _balanceText = State(initialValue: draft.balance == 0 ? "" : AmountInput.formatted(draft.balance.description) ?? "")
        _secondBalanceText = State(
            initialValue: draft.secondBalance == 0 ? "" : AmountInput.formatted(draft.secondBalance.description) ?? "",
        )
        self.principal = principal
        self.second = second
        self.isNew = isNew
        self.onSave = onSave
        self.onRemove = onRemove
        self.onClose = onClose
    }

    var body: some View {
        KWFormScreen(top: KWSpacing.xl, bottom: KWSpacing.xl) {
            VStack(alignment: .leading, spacing: KWSpacing.md) {
                KWFlowHeader(.close, action: onClose)
                Text(title)
                    .kwTextStyle(.titleSm)
                    .accessibilityAddTraits(.isHeader)
                fields
                if let message = validationMessage {
                    Text(message)
                        .font(KWTextStyle.caption.font)
                        .foregroundStyle(KWColor.State.negative)
                }
                if draft.kind == .credit, second != nil {
                    debtModes
                }
                if !isNew, draft.kind != .cash {
                    // Kept out of the footer so it never rides on the keyboard next to "Save".
                    Button(action: onRemove) { Text("Remove account", bundle: #bundle) }
                        .buttonStyle(.kw(.destructive, size: .row))
                }
            }
        } footer: {
            Button { save() } label: {
                isNew ? Text("Add", bundle: #bundle) : Text("Save", bundle: #bundle)
            }
            .buttonStyle(.kw())
            .disabled(!isValid)
        }
        .kwKeyboardToolbar($focus, order: focusOrder)
        .onChange(of: focus) { previous, _ in tidy(previous) }
        .onAppear {
            // A new account starts typing right away, as Revolut and Wise forms do.
            if isNew {
                focus = focusOrder.first
            }
        }
        .presentationBackground(KWColor.Surface.bg)
    }

    /// The fields on screen, in reading order, for the keyboard's next / previous arrows.
    var focusOrder: [Field] {
        var order: [Field] = draft.kind == .cash ? [] : [.bank, .name, .lastFour]
        order.append(.balance)
        if draft.kind == .credit, draft.debtMode == .dual, second != nil {
            order.append(.secondBalance)
        }
        return order
    }

    private var title: String {
        switch draft.kind {
        case .bank: String(localized: "Bank account", bundle: #bundle)
        case .credit: String(localized: "Credit card", bundle: #bundle)
        case .cash: String(localized: "Cash", bundle: #bundle)
        }
    }

    @ViewBuilder
    private var fields: some View {
        KWGroupedCard {
            if draft.kind != .cash {
                identityRows
            }
            if draft.kind == .bank, let second {
                currencyRow(options: [principal, second])
            }
            KWAmountFieldRow(balanceLabel, symbol: CurrencyFormatter.symbol(for: balanceCurrency), text: $balanceText)
                .kwFocused($focus, equals: .balance)
                .onTapGesture { focus = .balance }
            if draft.kind == .credit, draft.debtMode == .dual, let second {
                KWAmountFieldRow(debtLabel(second), symbol: CurrencyFormatter.symbol(for: second), text: $secondBalanceText)
                    .kwFocused($focus, equals: .secondBalance)
                    .onTapGesture { focus = .secondBalance }
            }
        }
        if draft.kind == .credit {
            KWFlowLayout(spacing: 6) {
                ForEach(CardNetwork.allCases, id: \.self) { network in
                    KWChip(Self.networkName(network), isSelected: draft.network == network) { draft.network = network }
                }
            }
        }
    }

    /// Bank, name and card ending; cash has none of them. Tapping anywhere on a row focuses its
    /// field, since the label takes most of the row.
    @ViewBuilder
    private var identityRows: some View {
        KWTextFieldRow(
            String(localized: "Bank", bundle: #bundle),
            placeholder: String(localized: "Bank name", bundle: #bundle),
            text: optionalBinding(\.bank),
        )
        .textInputAutocapitalization(.words)
        .autocorrectionDisabled()
        .kwFocused($focus, equals: .bank)
        .onTapGesture { focus = .bank }
        KWTextFieldRow(
            draft.kind == .credit ? String(localized: "Name", bundle: #bundle) : String(localized: "Account", bundle: #bundle),
            placeholder: draft.kind == .credit ? "Visa" : String(localized: "Savings", bundle: #bundle),
            text: $draft.name,
        )
        .textInputAutocapitalization(.words)
        .kwFocused($focus, equals: .name)
        .onTapGesture { focus = .name }
        KWTextFieldRow(
            draft.kind == .credit
                ? String(localized: "Last 4 digits", bundle: #bundle)
                : String(localized: "Debit, last 4", bundle: #bundle),
            placeholder: String(localized: "Optional", bundle: #bundle),
            text: optionalBinding(\.lastFour),
            digitLimit: 4,
            width: 110,
        )
        .kwFocused($focus, equals: .lastFour)
        .onTapGesture { focus = .lastFour }
    }

    /// The currency of the first amount field: the account's own, or the card's single debt
    /// currency.
    private var balanceCurrency: String {
        switch draft.kind {
        case .credit: draft.debtMode == .second ? second ?? principal : principal
        case .bank, .cash: draft.currency
        }
    }

    private var balanceLabel: String {
        switch draft.kind {
        case .credit: debtLabel(balanceCurrency)
        case .bank, .cash: String(localized: "Today's balance", bundle: #bundle)
        }
    }

    private func debtLabel(_ currency: String) -> String {
        String(localized: "Debt in \(currency)", bundle: #bundle)
    }

    private var debtModes: some View {
        VStack(alignment: .leading, spacing: KWSpacing.xs) {
            KWSectionHeader(String(localized: "Which currencies does it charge you in?", bundle: #bundle))
            ForEach([DebtMode.dual, .principal, .second], id: \.self) { mode in
                Button { draft.debtMode = mode } label: {
                    Text(modeTitle(mode))
                        .font(.kw(15, weight: 700))
                        .foregroundStyle(draft.debtMode == mode ? Color.black : KWColor.Text.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, KWSpacing.md)
                        .padding(.vertical, 14)
                        .background(
                            draft.debtMode == mode ? Color.white : KWColor.Surface.surface,
                            in: RoundedRectangle(cornerRadius: KWSpacing.md),
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: KWSpacing.md)
                                .strokeBorder(draft.debtMode == mode ? Color.white : KWColor.Surface.border),
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func modeTitle(_ mode: DebtMode) -> String {
        switch mode {
        case .dual: return String(localized: "Two currencies", bundle: #bundle)
        case .principal: return String(localized: "Only \(principal)", bundle: #bundle)
        case .second:
            let currency = second ?? principal
            return String(localized: "Only \(currency)", bundle: #bundle)
        }
    }

    private func currencyRow(options: [String]) -> some View {
        HStack {
            Text("Currency", bundle: #bundle).foregroundStyle(KWColor.Text.secondary)
            Spacer()
            KWSegmentedControl(options.map { (value: $0, title: $0) }, selection: $draft.currency, style: .accent)
        }
        .font(KWTextStyle.body.font)
        .padding(.vertical, 10)
    }

    private func optionalBinding(_ keyPath: WritableKeyPath<OnboardingAccountDraft, String?>) -> Binding<String> {
        Binding(get: { draft[keyPath: keyPath] ?? "" }, set: { draft[keyPath: keyPath] = $0.isEmpty ? nil : $0 })
    }

    private var isValid: Bool {
        let nameOK = draft.kind == .cash || !draft.name.trimmingCharacters(in: .whitespaces).isEmpty
        return nameOK && Self.problem(lastFour: draft.lastFour, balance: balanceText, secondBalance: secondBalanceText) == nil
    }

    /// Shown once the person leaves the field, so a half-typed value is not flagged mid-typing.
    private var validationMessage: String? {
        guard let problem = Self.problem(lastFour: draft.lastFour, balance: balanceText, secondBalance: secondBalanceText),
              focus != problem.field else { return nil }
        return switch problem {
        case .incompleteLastFour: String(localized: "Enter all 4 digits or leave it empty.", bundle: #bundle)
        case .invalidAmount, .invalidSecondAmount: String(localized: "Enter an amount like 1,250.50.", bundle: #bundle)
        }
    }

    /// Leaving an amount field shows it grouped ("10,000.00").
    private func tidy(_ field: Field?) {
        switch field {
        case .balance: balanceText = AmountInput.formatted(balanceText) ?? balanceText
        case .secondBalance: secondBalanceText = AmountInput.formatted(secondBalanceText) ?? secondBalanceText
        case .bank, .name, .lastFour, nil: break
        }
    }

    private func save() {
        focus = nil
        var result = draft
        result.balance = Self.amount(balanceText) ?? 0
        result.secondBalance = Self.amount(secondBalanceText) ?? 0
        onSave(result)
    }
}

extension AccountFormView {
    enum Problem: Equatable {
        case incompleteLastFour
        case invalidAmount
        case invalidSecondAmount

        var field: Field {
            switch self {
            case .incompleteLastFour: .lastFour
            case .invalidAmount: .balance
            case .invalidSecondAmount: .secondBalance
            }
        }
    }

    static func problem(lastFour: String?, balance: String, secondBalance: String) -> Problem? {
        if let lastFour, lastFour.count != 4 {
            return .incompleteLastFour
        }
        if amount(balance) == nil {
            return .invalidAmount
        }
        if amount(secondBalance) == nil {
            return .invalidSecondAmount
        }
        return nil
    }

    /// Empty means zero.
    static func amount(_ text: String) -> Decimal? {
        text.trimmingCharacters(in: .whitespaces).isEmpty ? 0 : AmountInput.decimal(from: text)
    }

    static func networkName(_ network: CardNetwork) -> String {
        switch network {
        case .visa: "Visa"
        case .mastercard: "Mastercard"
        case .amex: "Amex"
        case .other: String(localized: "Other", bundle: #bundle)
        }
    }
}
