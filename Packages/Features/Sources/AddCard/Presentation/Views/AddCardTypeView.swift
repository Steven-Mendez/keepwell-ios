import DesignSystem
import Domain
import SwiftUI

/// Step 1 · ¿Qué agregar?
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
                Text("¿Qué quieres agregar?")
                    .kwTextStyle(.titleSm)
                    .padding(.top, KWSpacing.xxs)
                    .accessibilityAddTraits(.isHeader)
                option(
                    palette: .azul,
                    title: "Tarjeta de crédito",
                    subtitle: "Es su propia cuenta: deuda en una o dos monedas, corte y pago",
                ) { viewModel.choose(.credit) }
                option(
                    palette: .coral,
                    title: "Tarjeta de débito",
                    subtitle: "Se vincula a una cuenta de banco; puede haber varias por cuenta",
                ) { viewModel.choose(.debit) }
                KWSectionHeader("Cuentas").padding(.top, KWSpacing.xs)
                HStack(spacing: 10) {
                    tile(.bank, "Cuenta de banco") { newAccountKind = .deposit }
                    tile(.cash, "Otra billetera") { newAccountKind = .cash }
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

/// "Cuenta de banco" / "Otra billetera": name, bank, currency and today's balance.
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
                Text(kind == .deposit ? "Cuenta de banco" : "Otra billetera").kwTextStyle(.titleSm)
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
                FormTextRow(label: "Banco", placeholder: "Nombre del banco", text: $bank)
            }
            FormTextRow(label: "Nombre", placeholder: kind == .deposit ? "Ahorro" : "Sobre", text: $name)
            if let second = viewModel.second {
                HStack {
                    Text("Moneda").foregroundStyle(KWColor.Text.secondary)
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
            FormAmountRow(label: "Saldo de hoy", text: $balanceText)
        }
    }

    private var addButton: some View {
        Button("Agregar") {
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
