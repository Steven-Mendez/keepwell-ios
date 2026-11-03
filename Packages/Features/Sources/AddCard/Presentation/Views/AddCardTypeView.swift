import Core
import DesignSystem
import Domain
import SwiftUI

/// Step 1 · What to add?
public struct AddCardTypeView: View {
    private let viewModel: AddCardViewModel
    private let onClose: () -> Void
    @State private var isAddingWallet = false

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
                    subtitle: String(localized: "Your bank account, shown as its card: balance, bank and last 4", bundle: #bundle),
                ) { viewModel.choose(.debit) }
                KWSectionHeader(String(localized: "Without a card", bundle: #bundle)).padding(.top, KWSpacing.xs)
                tile(.cash, String(localized: "Other wallet", bundle: #bundle)) { isAddingWallet = true }
            }
        }
        .sheet(isPresented: $isAddingWallet) {
            NewWalletSheet(viewModel: viewModel) { isAddingWallet = false }
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

/// "Other wallet": cash kept somewhere other than the main wallet, with a name, currency and
/// today's balance. Bank accounts come with their card instead, from "Debit card".
struct NewWalletSheet: View {
    let viewModel: AddCardViewModel
    let onClose: () -> Void
    @State private var name = ""
    @State private var currency = ""
    @State private var balanceText = ""
    @State private var isSaving = false
    @FocusState private var focus: Field?

    private enum Field: Hashable {
        case name
        case balance
    }

    var body: some View {
        KWFormScreen(top: KWSpacing.xl, bottom: KWSpacing.xl) {
            VStack(alignment: .leading, spacing: KWSpacing.md) {
                KWFlowHeader(.close, action: onClose)
                Text("Other wallet", bundle: #bundle).kwTextStyle(.titleSm)
                fields
                if let error = viewModel.errorMessage {
                    Text(error).font(KWTextStyle.caption.font).foregroundStyle(KWColor.State.negative)
                }
            }
        } footer: {
            addButton
        }
        .kwKeyboardToolbar($focus, order: [.name, .balance])
        .onAppear { focus = .name }
    }

    private var fields: some View {
        KWGroupedCard {
            KWTextFieldRow(
                String(localized: "Name", bundle: #bundle),
                placeholder: String(localized: "Envelope", bundle: #bundle),
                text: $name,
            )
            .textInputAutocapitalization(.words)
            .kwFocused($focus, equals: .name)
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
            KWAmountFieldRow(
                String(localized: "Today's balance", bundle: #bundle),
                symbol: CurrencyFormatter.symbol(for: currencyBinding.wrappedValue),
                text: $balanceText,
            )
            .kwFocused($focus, equals: .balance)
        }
    }

    private var addButton: some View {
        Button {
            focus = nil
            isSaving = true
            Task {
                let saved = await viewModel.createWallet(
                    name: name,
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
            get: { currency.isEmpty ? viewModel.second ?? viewModel.principal : currency },
            set: { currency = $0 },
        )
    }
}
