import DesignSystem
import Domain
import SettingsDomain
import SwiftUI

/// Currencies, the rate between them, when to be reminded of a card's payment, and the home zone.
struct MoneySection: View {
    @Bindable var viewModel: SettingsViewModel
    let overview: SettingsOverview
    @State private var isConfirmingSwap = false
    @State private var picking: CurrencyTarget?
    @FocusState private var isEditingRate: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private enum CurrencyTarget: Identifiable {
        case main
        case second

        var id: Self { self }
    }

    private var settings: Settings {
        overview.settings
    }

    var body: some View {
        SettingsSection(
            title: String(localized: "Money", bundle: #bundle),
            footnote: settings.currencies.second == nil ? nil : viewModel.rateFootnote,
        ) {
            KWGroupedCard {
                currencyRow(.main)
                currencyRow(.second)
                if let second = settings.currencies.second {
                    rateRow(settings.currencies)
                    swapRow(second)
                }
                SettingsMenuRow(
                    label: String(localized: "Remind me to pay", bundle: #bundle),
                    description: String(localized: "Credit cards", bundle: #bundle),
                    icon: .bell,
                    tint: KWSettingsTint.reminders,
                    value: viewModel.reminderTitle(settings.paymentReminderDaysBefore),
                    options: SettingsViewModel.reminderOptions,
                    title: viewModel.reminderTitle,
                ) { days in Task { await viewModel.setReminderDays(days) } }
                TimeZoneRow(viewModel: viewModel, settings: settings)
            }
        }
        .onChange(of: isEditingRate) { _, editing in
            if !editing {
                Task { await viewModel.commitRate() }
            }
        }
        .sheet(item: $picking) { target in
            picker(for: target)
                .presentationDetents([.large])
                .presentationBackground(KWColor.Surface.bg)
        }
    }

    /// Changing a currency is offered only while nothing is kept in it; otherwise the row says why.
    private func currencyRow(_ target: CurrencyTarget) -> some View {
        let isMain = target == .main
        let code = isMain ? settings.currencies.principal : settings.currencies.second
        let canChange = isMain ? overview.canChangeMainCurrency : overview.canChangeSecondCurrency
        let row = KWSettingsRow(
            isMain ? String(localized: "Main currency", bundle: #bundle) : String(localized: "Second currency", bundle: #bundle),
            description: canChange ? nil : String(localized: "Used by your accounts, so it can't change here.", bundle: #bundle),
            icon: .cash,
            tint: isMain ? KWSettingsTint.money : KWSettingsTint.organization,
            value: code.map(viewModel.currencyName) ?? String(localized: "None", bundle: #bundle),
            accessory: canChange ? .chevron : nil,
        )
        return Group {
            if canChange {
                Button { picking = target } label: { row }
                    .buttonStyle(.plain)
            } else {
                row
            }
        }
    }

    @ViewBuilder
    private func picker(for target: CurrencyTarget) -> some View {
        switch target {
        case .main:
            SettingsCurrencyPicker(
                title: String(localized: "Main currency", bundle: #bundle),
                selected: settings.currencies.principal,
                excluding: settings.currencies.second,
                allowsNone: false,
                name: viewModel.currencyName,
            ) { code in
                picking = nil
                Task { await viewModel.changeCurrency(.main(code ?? settings.currencies.principal)) }
            }
        case .second:
            SettingsCurrencyPicker(
                title: String(localized: "Second currency", bundle: #bundle),
                selected: settings.currencies.second,
                excluding: settings.currencies.principal,
                allowsNone: true,
                name: viewModel.currencyName,
            ) { code in
                picking = nil
                Task { await viewModel.changeCurrency(.second(code)) }
            }
        }
    }

    private func swapRow(_ second: String) -> some View {
        Button { isConfirmingSwap = true } label: {
            KWSettingsRow(
                String(localized: "Make \(second) the main currency", bundle: #bundle),
                icon: .transfer,
                tint: KWSettingsTint.data,
                accessory: .chevron,
            )
        }
        .buttonStyle(.plain)
        .confirmationDialog(
            String(localized: "Make \(second) the main currency?", bundle: #bundle),
            isPresented: $isConfirmingSwap,
            titleVisibility: .visible,
        ) {
            Button { Task { await viewModel.swapCurrencies() } } label: {
                Text("Swap currencies", bundle: #bundle)
            }
        } message: {
            Text(
                "Net worth, summaries and new movements will be in \(second), and the rate is turned around. Past movements keep the rate they were logged with.",
                bundle: #bundle,
            )
        }
    }

    /// "1 USD = [36.6243] NIO", as the design has it: the title is the left side of the rate.
    private func rateRow(_ currencies: CurrencySettings) -> some View {
        KWSettingsRow(
            "1 \(currencies.principal) =",
            description: String(localized: "Manual · default 1", bundle: #bundle),
            icon: .chartBars,
            tint: KWSettingsTint.money,
        ) {
            HStack(spacing: KWSpacing.xs) {
                TextField(String(localized: "Rate", bundle: #bundle), text: $viewModel.rateText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .font(KWTextStyle.body.font.weight(.semibold))
                    .monospacedDigit()
                    .focused($isEditingRate)
                    .padding(.vertical, 6)
                    .padding(.horizontal, KWSpacing.xs)
                    // Under the title at the largest sizes, where the rate gets the whole width.
                    .frame(minWidth: 84, maxWidth: dynamicTypeSize.isAccessibilitySize ? 220 : 110)
                    .background(KWColor.Surface.surface2, in: RoundedRectangle(cornerRadius: 10))
                Text(currencies.second ?? "")
                    .font(KWTextStyle.body.font.weight(.semibold))
                    .fixedSize()
            }
        }
    }
}
