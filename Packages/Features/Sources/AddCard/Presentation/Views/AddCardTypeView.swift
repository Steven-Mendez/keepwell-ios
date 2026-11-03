import DesignSystem
import Domain
import SwiftUI

/// Step 1 · What to add?
public struct AddCardTypeView: View {
    private let viewModel: AddCardViewModel
    private let onClose: () -> Void
    @State private var newAccountKind: AccountKind?

    public init(viewModel: AddCardViewModel, onClose: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onClose = onClose
    }

    public var body: some View {
        KWScreen(bottom: 34) {
            VStack(alignment: .leading, spacing: 14) {
                KWFlowHeader(.close, action: onClose)
                Text("What do you want to add?", bundle: #bundle)
                    .kwTextStyle(.titleSm)
                    .padding(.top, KWSpacing.xxs)
                    .accessibilityAddTraits(.isHeader)
                option(
                    palette: .azul,
                    title: String(localized: "Credit card", bundle: #bundle),
                    subtitle: String(
                        localized: "It's its own account: debt in one or two currencies, cutoff and due dates",
                        bundle: #bundle,
                    ),
                ) { viewModel.choose(.credit) }
                option(
                    palette: .coral,
                    title: String(localized: "Debit card", bundle: #bundle),
                    subtitle: String(localized: "Linked to a bank account; an account can have several", bundle: #bundle),
                ) { viewModel.choose(.debit) }
                KWSectionHeader(String(localized: "Accounts", bundle: #bundle)).padding(.top, KWSpacing.xs)
                HStack(spacing: 10) {
                    tile(.bank, String(localized: "Bank account", bundle: #bundle)) { newAccountKind = .deposit }
                    tile(.cash, String(localized: "Other wallet", bundle: #bundle)) { newAccountKind = .cash }
                }
            }
        }
        .sheet(item: $newAccountKind) { kind in
            NewAccountSheet(viewModel: viewModel, kind: kind) { newAccountKind = nil }
                .presentationDetents([.medium, .large])
                .presentationBackground(KWColor.Surface.bg)
        }
    }

    private func option(palette: KWColor.CardArt, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                KWMiniCard(.palette(palette), size: .medium)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(KWTextStyle.heading.font)
                    Text(subtitle)
                        .font(KWTextStyle.caption.font.weight(.regular))
                        .foregroundStyle(KWColor.Text.muted)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .foregroundStyle(KWColor.Text.primary)
            .padding(KWSpacing.md)
            .background(KWColor.Surface.surface, in: RoundedRectangle(cornerRadius: KWRadius.surface))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func tile(_ icon: KWIcon, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                KWIconView(icon, size: 22)
                Text(title).font(KWTextStyle.label.font)
            }
            .foregroundStyle(KWColor.Text.primary)
            .frame(maxWidth: .infinity)
            .frame(height: 80)
            .background(KWColor.Surface.surface, in: RoundedRectangle(cornerRadius: KWRadius.card))
        }
        .buttonStyle(.plain)
    }
}

extension AccountKind: @retroactive Identifiable {
    public var id: String { rawValue }
}

/// "Bank account" / "Other wallet": name, bank, currency and today's balance.
struct NewAccountSheet: View {
    let viewModel: AddCardViewModel
    let kind: AccountKind
    let onClose: () -> Void
    @State private var name = ""
    @State private var bank = ""
    @State private var currency = ""
    @State private var balanceText = ""
    @State private var isSaving = false

    var body: some View {
        KWScreen(top: KWSpacing.xl, bottom: KWSpacing.xl) {
            VStack(alignment: .leading, spacing: KWSpacing.md) {
                KWFlowHeader(.close, action: onClose)
                Text(kind == .deposit ? "Bank account" : "Other wallet", bundle: #bundle).kwTextStyle(.titleSm)
                fields
                if let error = viewModel.errorMessage {
                    Text(error).font(KWTextStyle.caption.font).foregroundStyle(KWColor.State.negative)
                }
                Spacer(minLength: 0)
                addButton
            }
        }
    }

    private var fields: some View {
        KWGroupedCard {
            if kind == .deposit {
                FormTextRow(
                    label: String(localized: "Bank", bundle: #bundle),
                    placeholder: String(localized: "Bank name", bundle: #bundle),
                    text: $bank,
                )
            }
            FormTextRow(label: String(localized: "Name", bundle: #bundle), placeholder: namePlaceholder, text: $name)
            if let second = viewModel.second {
                HStack {
                    Text("Currency", bundle: #bundle).foregroundStyle(KWColor.Text.secondary)
                    Spacer()
                    KWSegmentedControl(
                        [(value: viewModel.principal, title: viewModel.principal), (value: second, title: second)],
                        selection: currencyBinding,
                        style: .accent,
                    )
                }
                .font(KWTextStyle.body.font)
                .padding(.vertical, 10)
            }
            FormAmountRow(label: String(localized: "Today's balance", bundle: #bundle), text: $balanceText)
        }
    }

    private var namePlaceholder: String {
        kind == .deposit ? String(localized: "Savings", bundle: #bundle) : String(localized: "Envelope", bundle: #bundle)
    }

    private var addButton: some View {
        Button {
            isSaving = true
            Task {
                let saved = await viewModel.createAccount(
                    kind: kind,
                    name: name,
                    bank: bank.isEmpty ? nil : bank,
                    currency: currencyBinding.wrappedValue,
                    balanceText: balanceText,
                )
                isSaving = false
                if saved {
                    onClose()
                }
            }
        } label: {
            Text("Add", bundle: #bundle)
        }
        .buttonStyle(.kw())
        .disabled(isSaving || name.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    private var currencyBinding: Binding<String> {
        Binding(
            get: { currency.isEmpty ? (kind == .cash ? viewModel.second ?? viewModel.principal : viewModel.principal) : currency },
            set: { currency = $0 },
        )
    }
}
