import Core
import DesignSystem
import Domain
import OnboardingDomain
import SwiftUI

/// Sheet to add or edit one onboarding account. Built from the add-card form patterns (grouped
/// rows with trailing inputs, chips, debt mode cards) since the design has no separate screen.
struct AccountFormView: View {
    @State private var draft: OnboardingAccountDraft
    @State private var balanceText: String
    @State private var secondBalanceText: String
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
        _balanceText = State(initialValue: draft.balance == 0 ? "" : draft.balance.description)
        _secondBalanceText = State(initialValue: draft.secondBalance == 0 ? "" : draft.secondBalance.description)
        self.principal = principal
        self.second = second
        self.isNew = isNew
        self.onSave = onSave
        self.onRemove = onRemove
        self.onClose = onClose
    }

    var body: some View {
        KWScreen(top: KWSpacing.xl, bottom: KWSpacing.xl) {
            VStack(spacing: KWSpacing.sm) {
                ScrollView {
                    VStack(alignment: .leading, spacing: KWSpacing.md) {
                        KWFlowHeader(.close, action: onClose)
                        Text(title)
                            .kwTextStyle(.titleSm)
                            .accessibilityAddTraits(.isHeader)
                        fields
                        if draft.kind == .credit, second != nil {
                            debtModes
                        }
                    }
                }
                .scrollIndicators(.hidden)
                VStack(spacing: KWSpacing.xs) {
                    Button { save() } label: {
                        isNew ? Text("Add", bundle: #bundle) : Text("Save", bundle: #bundle)
                    }
                    .buttonStyle(.kw())
                    .disabled(!isValid)
                    if !isNew, draft.kind != .cash {
                        Button(action: onRemove) { Text("Remove account", bundle: #bundle) }
                            .buttonStyle(.kw(.destructive, size: .row))
                    }
                }
            }
        }
        .presentationBackground(KWColor.Surface.bg)
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
                textRow(
                    String(localized: "Bank", bundle: #bundle),
                    text: optionalBinding(\.bank),
                    placeholder: String(localized: "Bank name", bundle: #bundle),
                )
                textRow(
                    draft.kind == .credit ? String(localized: "Name", bundle: #bundle) : String(localized: "Account", bundle: #bundle),
                    text: $draft.name,
                    placeholder: draft.kind == .credit ? "Visa" : String(localized: "Savings", bundle: #bundle),
                )
                textRow(
                    draft.kind == .credit
                        ? String(localized: "Last 4 digits", bundle: #bundle)
                        : String(localized: "Debit, last 4", bundle: #bundle),
                    text: optionalBinding(\.lastFour),
                    placeholder: String(localized: "Optional", bundle: #bundle),
                    numeric: true,
                )
            }
            if draft.kind == .bank, let second {
                currencyRow(options: [principal, second])
            }
            amountRow(balanceLabel, text: $balanceText)
            if draft.kind == .credit, draft.debtMode == .dual, let second {
                amountRow(debtLabel(second), text: $secondBalanceText)
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

    private var balanceLabel: String {
        switch draft.kind {
        case .credit:
            debtLabel(draft.debtMode == .second ? second ?? principal : principal)
        case .bank, .cash:
            todaysBalanceLabel(currency: draft.currency)
        }
    }

    private func debtLabel(_ currency: String) -> String {
        String(localized: "Debt in \(currency)", bundle: #bundle)
    }

    private func todaysBalanceLabel(currency: String) -> String {
        String(localized: "Today's balance (\(currency))", bundle: #bundle)
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

    private func textRow(_ label: String, text: Binding<String>, placeholder: String, numeric: Bool = false) -> some View {
        HStack(spacing: KWSpacing.sm) {
            Text(label).foregroundStyle(KWColor.Text.secondary)
            TextField(placeholder, text: text)
                .multilineTextAlignment(.trailing)
                .font(.kw(15, weight: 600))
                .keyboardType(numeric ? .numberPad : .default)
        }
        .font(KWTextStyle.body.font)
        .padding(.vertical, KWSpacing.sm)
    }

    private func amountRow(_ label: String, text: Binding<String>) -> some View {
        HStack(spacing: KWSpacing.sm) {
            Text(label).foregroundStyle(KWColor.Text.secondary)
            Spacer()
            TextField(label, text: text, prompt: Text(verbatim: "0.00"))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(.kw(15, weight: 600))
                .monospacedDigit()
                .padding(.vertical, KWSpacing.xs)
                .padding(.horizontal, 10)
                .frame(width: 120)
                .background(KWColor.Surface.surface2, in: RoundedRectangle(cornerRadius: 10))
        }
        .font(KWTextStyle.body.font)
        .padding(.vertical, KWSpacing.sm)
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
        let lastFourOK = draft.lastFour.map { $0.count == 4 && $0.allSatisfy(\.isNumber) } ?? true
        let nameOK = draft.kind == .cash || !draft.name.trimmingCharacters(in: .whitespaces).isEmpty
        return lastFourOK && nameOK && Self.amount(balanceText) != nil && Self.amount(secondBalanceText) != nil
    }

    private func save() {
        var result = draft
        result.balance = Self.amount(balanceText) ?? 0
        result.secondBalance = Self.amount(secondBalanceText) ?? 0
        onSave(result)
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
