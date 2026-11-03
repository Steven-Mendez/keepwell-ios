import DesignSystem
import SwiftUI

/// Step 2 · Monedas y tasa.
public struct CurrenciesView: View {
    @Bindable private var viewModel: OnboardingViewModel
    private let onBack: () -> Void
    @State private var isSearching = false

    public init(viewModel: OnboardingViewModel, onBack: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onBack = onBack
    }

    public var body: some View {
        KWScreen(bottom: 40) {
            VStack(alignment: .leading, spacing: 18) {
                KWFlowHeader(.back, progress: (3, 1), action: onBack)
                OnboardingHeading(
                    title: "¿Con qué monedas trabajas?",
                    message: "Los reportes y el patrimonio se calculan en la moneda principal.",
                )
                principalRow
                KWSectionHeader("Segunda moneda")
                    .padding(.top, KWSpacing.xxs)
                KWFlowLayout {
                    ForEach(viewModel.secondCurrencyOptions) { option in
                        KWChip(option.label, isSelected: option.code == viewModel.second, style: .outlined, height: 38) {
                            viewModel.selectSecond(option.code)
                        }
                    }
                    KWChip("Buscar…", isSelected: false, style: .outlined, height: 38) { isSearching = true }
                }
                if viewModel.second != nil {
                    rateCard
                }
                Spacer(minLength: 0)
                Button("Continuar") {
                    KWKeyboard.dismiss()
                    viewModel.continueFromCurrencies()
                }
                .buttonStyle(.kw())
                .disabled(!viewModel.canContinueFromCurrencies)
            }
        }
        .sheet(isPresented: $isSearching) {
            CurrencySearchView(excluding: viewModel.principal) { code in
                viewModel.selectSecond(code)
                isSearching = false
            }
        }
    }

    private var principalRow: some View {
        Menu {
            ForEach(["USD", "EUR", "MXN", "COP", "NIO", "CRC", "GTQ", "HNL"], id: \.self) { code in
                Button(code) { viewModel.selectPrincipal(code) }
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Moneda principal")
                        .font(KWTextStyle.caption.font)
                        .foregroundStyle(KWColor.Text.muted)
                    Text(viewModel.principalLabel)
                        .font(KWTextStyle.heading.font)
                        .foregroundStyle(KWColor.Text.primary)
                }
                Spacer()
                Text(verbatim: "›").foregroundStyle(KWColor.Text.muted)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, KWSpacing.md)
            .background(KWColor.Surface.surface, in: RoundedRectangle(cornerRadius: KWRadius.surface))
        }
    }

    private var rateCard: some View {
        VStack(alignment: .leading, spacing: KWSpacing.sm) {
            Text("Tasa de cambio (la pones tú)")
                .font(KWTextStyle.caption.font)
                .foregroundStyle(KWColor.Text.muted)
            HStack(spacing: 10) {
                Text(verbatim: "1 \(viewModel.principal) =")
                TextField("1.0000", text: $viewModel.rateText)
                    .keyboardType(.decimalPad)
                    .monospacedDigit()
                    .padding(.horizontal, 14)
                    .frame(height: 48)
                    .background(KWColor.Surface.surface2, in: RoundedRectangle(cornerRadius: KWRadius.input))
                    .accessibilityLabel("Tasa de cambio")
                Text(viewModel.second ?? "")
            }
            .font(.kw(20, weight: 700, relativeTo: .title3))
            Button {
                viewModel.useNicaraguaExample()
            } label: {
                Text("Ejemplo Nicaragua: 1 USD = 36.6243 NIO")
                    .font(.kw(13, weight: 600, relativeTo: .footnote))
                    .foregroundStyle(KWColor.Brand.linkHover)
                    .padding(.horizontal, KWSpacing.sm)
                    .frame(height: 32)
                    .background(KWColor.Tint.accent, in: Capsule())
            }
            .buttonStyle(.plain)
            Text("Por defecto es 1. Cámbiala cuando quieras; cada movimiento guarda la tasa del momento en que lo anotaste.")
                .font(KWTextStyle.captionSm.font)
                .foregroundStyle(KWColor.Text.muted)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(KWSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(KWColor.Surface.surface, in: RoundedRectangle(cornerRadius: KWRadius.surface))
    }
}

/// "Buscar…": every ISO currency, searchable by code or name.
struct CurrencySearchView: View {
    let excluding: String
    let onPick: (String) -> Void
    @State private var query = ""

    private var currencies: [(code: String, name: String)] {
        let spanish = Locale(identifier: "es")
        return Locale.commonISOCurrencyCodes
            .filter { $0 != excluding }
            .map { ($0, spanish.localizedString(forCurrencyCode: $0) ?? $0) }
            .filter { query.isEmpty || $0.code.localizedCaseInsensitiveContains(query) || $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            List(currencies, id: \.code) { currency in
                Button {
                    onPick(currency.code)
                } label: {
                    HStack {
                        Text(currency.code).font(.kw(15, weight: 700))
                        Text(currency.name.prefix(1).uppercased() + currency.name.dropFirst())
                            .font(KWTextStyle.body.font)
                            .foregroundStyle(KWColor.Text.secondary)
                    }
                }
                .listRowBackground(KWColor.Surface.surface)
            }
            .scrollContentBackground(.hidden)
            .background(KWColor.Surface.bg)
            .searchable(text: $query, prompt: "Buscar moneda")
            .navigationTitle("Segunda moneda")
            .navigationBarTitleDisplayMode(.inline)
        }
        .preferredColorScheme(.dark)
    }
}
