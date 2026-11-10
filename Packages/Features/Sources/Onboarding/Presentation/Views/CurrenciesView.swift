import DesignSystem
import SwiftUI

/// Step 3 · Currencies and rate. One currency is a first-class choice; the second currency, the
/// swap and the rate only appear once the person says they use two.
public struct CurrenciesView: View {
    @Bindable private var viewModel: OnboardingViewModel
    private let onBack: () -> Void
    @State private var picking: PickerTarget?
    @FocusState private var rateFocused: Bool

    private enum PickerTarget: Identifiable {
        case principal
        case second

        var id: Self { self }
    }

    public init(viewModel: OnboardingViewModel, onBack: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onBack = onBack
    }

    public var body: some View {
        KWFormScreen(bottom: 40) {
            VStack(alignment: .leading, spacing: 18) {
                KWFlowHeader(.back, progress: (5, 2), action: onBack)
                OnboardingHeading(
                    title: String(localized: "Which currencies do you use?", bundle: #bundle),
                    message: String(localized: "Reports and net worth are calculated in the main currency.", bundle: #bundle),
                )
                KWSegmentedControl(
                    [
                        (value: OnboardingViewModel.CurrencyMode.single, title: String(localized: "One currency", bundle: #bundle)),
                        (value: .dual, title: String(localized: "Two currencies", bundle: #bundle)),
                    ],
                    selection: Binding(get: { viewModel.currencyMode }, set: { viewModel.setCurrencyMode($0) }),
                )
                principalRow
                if viewModel.second != nil {
                    secondCurrency
                    rateCard
                }
            }
        } footer: {
            Button {
                KWKeyboard.dismiss()
                viewModel.continueFromCurrencies()
            } label: {
                Text("Continue", bundle: #bundle)
            }
            .buttonStyle(.kw())
            .disabled(!viewModel.canContinueFromCurrencies)
        }
        .sheet(item: $picking) { target in
            currencyPicker(for: target)
        }
    }

    @ViewBuilder
    private func currencyPicker(for target: PickerTarget) -> some View {
        switch target {
        case .principal:
            CurrencyPickerView(
                title: String(localized: "Main currency", bundle: #bundle),
                common: viewModel.principalOptions,
                selected: viewModel.principal,
                excluding: nil,
            ) { code in
                viewModel.selectPrincipal(code)
                picking = nil
            }
        case .second:
            CurrencyPickerView(
                title: String(localized: "Second currency", bundle: #bundle),
                common: viewModel.secondCurrencyOptions,
                selected: viewModel.secondChoice,
                excluding: viewModel.principal,
            ) { code in
                viewModel.selectSecond(code)
                picking = nil
            }
        }
    }

    private var principalRow: some View {
        Button {
            KWKeyboard.dismiss()
            picking = .principal
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Main currency", bundle: #bundle)
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
            .contentShape(RoundedRectangle(cornerRadius: KWRadius.surface))
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("Choose your main currency", bundle: #bundle))
    }

    @ViewBuilder
    private var secondCurrency: some View {
        KWSectionHeader(String(localized: "Second currency", bundle: #bundle)) {
            Button {
                KWKeyboard.dismiss()
                viewModel.swapCurrencies()
            } label: {
                HStack(spacing: 6) {
                    KWIconView(.transfer, size: 15)
                    Text("Swap", bundle: #bundle)
                }
                .font(.kw(13, weight: 600, relativeTo: .footnote))
                .foregroundStyle(KWColor.Brand.linkHover)
                .padding(.horizontal, KWSpacing.sm)
                .frame(height: 30)
                .background(KWColor.Tint.accent, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Swap main and second currency", bundle: #bundle))
        }
        .padding(.top, KWSpacing.xxs)
        KWFlowLayout {
            ForEach(viewModel.secondCurrencyOptions, id: \.self) { code in
                KWChip(code, isSelected: code == viewModel.second, style: .outlined, height: 38) {
                    viewModel.selectSecond(code)
                }
            }
            KWChip(String(localized: "Search…", bundle: #bundle), isSelected: false, style: .outlined, height: 38) {
                KWKeyboard.dismiss()
                picking = .second
            }
        }
    }

    private var rateCard: some View {
        VStack(alignment: .leading, spacing: KWSpacing.sm) {
            Text("Exchange rate (you set it)", bundle: #bundle)
                .font(KWTextStyle.caption.font)
                .foregroundStyle(KWColor.Text.muted)
            HStack(spacing: 10) {
                Text(verbatim: "1 \(viewModel.principal) =")
                TextField("1.0000", text: $viewModel.rateText)
                    .keyboardType(.decimalPad)
                    .monospacedDigit()
                    .focused($rateFocused)
                    .padding(.horizontal, 14)
                    .frame(height: 48)
                    .background(KWColor.Surface.surface2, in: RoundedRectangle(cornerRadius: KWRadius.input))
                    // The padding is part of the box the person sees, so a tap anywhere in it edits.
                    .contentShape(RoundedRectangle(cornerRadius: KWRadius.input))
                    .onTapGesture { rateFocused = true }
                    .accessibilityLabel(Text("Exchange rate", bundle: #bundle))
                Text(viewModel.second ?? "")
            }
            .font(.kw(20, weight: 700, relativeTo: .title3))
            Text("It defaults to 1. Change it whenever you want; each transaction keeps the rate from when you logged it.", bundle: #bundle)
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

/// Every ISO currency, searchable by code or name, with the common ones on top so most people
/// never need to search.
struct CurrencyPickerView: View {
    let title: String
    let common: [String]
    let selected: String
    let excluding: String?
    let onPick: (String) -> Void
    @State private var query = ""

    private var all: [String] {
        Locale.commonISOCurrencyCodes.filter { $0 != excluding }
    }

    private var matches: [String] {
        all.filter { code in
            code.localizedCaseInsensitiveContains(query)
                || OnboardingViewModel.fullName(for: code).localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if query.isEmpty {
                    Section {
                        rows(common.filter { $0 != excluding })
                    } header: {
                        Text("Common", bundle: #bundle)
                    }
                    Section {
                        rows(all)
                    } header: {
                        Text("All currencies", bundle: #bundle)
                    }
                } else {
                    rows(matches)
                }
            }
            .scrollContentBackground(.hidden)
            .background(KWColor.Surface.bg)
            .searchable(text: $query, prompt: Text("Search currency", bundle: #bundle))
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func rows(_ codes: [String]) -> some View {
        ForEach(codes, id: \.self) { code in
            Button {
                onPick(code)
            } label: {
                HStack {
                    Text(code).font(.kw(15, weight: 700))
                    Text(OnboardingViewModel.fullName(for: code))
                        .font(KWTextStyle.body.font)
                        .foregroundStyle(KWColor.Text.secondary)
                    Spacer()
                    if code == selected {
                        KWIconView(.check, size: 16)
                            .foregroundStyle(KWColor.Brand.linkHover)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(code == selected ? .isSelected : [])
            .listRowBackground(KWColor.Surface.surface)
        }
    }
}
