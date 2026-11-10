import DesignSystem
import Domain
import SettingsDomain
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// A muted section title over its card, and an optional footnote under it.
struct SettingsSection<Content: View>: View {
    let title: String
    var footnote: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: KWSpacing.xs) {
            KWSectionHeader(title).padding(.leading, KWSpacing.xxs)
            content
            if let footnote {
                Text(footnote)
                    .font(KWTextStyle.captionSm.font.weight(.regular))
                    .foregroundStyle(KWColor.Text.muted)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, KWSpacing.xxs)
            }
        }
    }
}

/// A settings row whose value opens a menu of fixed choices.
struct SettingsMenuRow<Option: Hashable>: View {
    let label: String
    let icon: KWIcon
    let tint: Color
    let value: String
    let options: [Option]
    let title: (Option) -> String
    let select: (Option) -> Void

    var body: some View {
        Menu {
            ForEach(options, id: \.self) { option in
                Button(title(option)) { select(option) }
            }
        } label: {
            KWSettingsRow(label, icon: icon, tint: tint, value: value, accessory: .chevron)
        }
        .buttonStyle(.plain)
    }
}

/// Who the app greets and in which language.
struct ProfileSection: View {
    @Bindable var viewModel: SettingsViewModel
    @FocusState private var isEditingName: Bool
    @Environment(\.openURL) private var openURL

    var body: some View {
        SettingsSection(
            title: String(localized: "Profile & preferences", bundle: #bundle),
            footnote: String(
                localized: "Keepwell uses your iPhone's language. To use another one only here, choose it in iPhone Settings.",
                bundle: #bundle,
            ),
        ) {
            KWGroupedCard {
                nameRow
                // iOS lets each app use its own language from the app's page in iPhone Settings,
                // and reopens the app in it; the row leads there.
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                } label: {
                    KWSettingsRow(
                        String(localized: "App language", bundle: #bundle),
                        icon: .globe,
                        tint: KWSettingsTint.profile,
                        value: viewModel.languageName,
                        accessory: .external,
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .onChange(of: isEditingName) { _, editing in
            if !editing {
                Task { await viewModel.commitName() }
            }
        }
    }

    /// The name the lock screen, home and the cards greet with ("Good morning, Steven").
    private var nameRow: some View {
        KWSettingsRow(String(localized: "Your name", bundle: #bundle), icon: .person, tint: KWSettingsTint.profile) {
            TextField(String(localized: "For the greeting", bundle: #bundle), text: $viewModel.nameText)
                .multilineTextAlignment(.trailing)
                .font(KWTextStyle.body.font.weight(.semibold))
                .textContentType(.givenName)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused($isEditingName)
                .frame(maxWidth: 170)
        }
    }
}

/// Currencies, the rate between them, and when to be reminded of a card's payment.
struct MoneySection: View {
    @Bindable var viewModel: SettingsViewModel
    let settings: Settings
    @State private var isConfirmingSwap = false
    @FocusState private var isEditingRate: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        SettingsSection(
            title: String(localized: "Money", bundle: #bundle),
            footnote: settings.currencies.second == nil ? nil : viewModel.rateFootnote,
        ) {
            KWGroupedCard {
                KWSettingsRow(
                    String(localized: "Main currency", bundle: #bundle),
                    icon: .cash,
                    tint: KWSettingsTint.money,
                    value: viewModel.currencyName(settings.currencies.principal),
                )
                if let second = settings.currencies.second {
                    KWSettingsRow(
                        String(localized: "Second currency", bundle: #bundle),
                        icon: .cash,
                        tint: KWSettingsTint.organization,
                        value: viewModel.currencyName(second),
                    )
                    rateRow(settings.currencies)
                    swapRow(second)
                }
                SettingsMenuRow(
                    label: String(localized: "Remind me to pay", bundle: #bundle),
                    icon: .bell,
                    tint: KWSettingsTint.reminders,
                    value: viewModel.reminderTitle(settings.paymentReminderDaysBefore),
                    options: SettingsViewModel.reminderOptions,
                    title: viewModel.reminderTitle,
                ) { days in Task { await viewModel.setReminderDays(days) } }
            }
        }
        .onChange(of: isEditingRate) { _, editing in
            if !editing {
                Task { await viewModel.commitRate() }
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

/// How the app unlocks, when it asks again and whether amounts hide in the app switcher.
struct SecuritySection: View {
    @Bindable var viewModel: SettingsViewModel
    let overview: SettingsOverview
    let onSetUpPasscode: () -> Void
    @State private var isConfirmingPasscodeOff = false

    private var settings: Settings {
        overview.settings
    }

    var body: some View {
        SettingsSection(title: String(localized: "Security", bundle: #bundle)) {
            KWGroupedCard {
                unlockPicker
                if settings.unlockMethod != .disabled {
                    passcodeRow
                    SettingsMenuRow(
                        label: String(localized: "Ask again after", bundle: #bundle),
                        icon: .clock,
                        tint: KWSettingsTint.security,
                        value: viewModel.relockTitle(settings.relockAfter),
                        options: SettingsViewModel.relockOptions,
                        title: viewModel.relockTitle,
                    ) { seconds in Task { await viewModel.setRelockAfter(seconds) } }
                }
                hideAmountsToggle
            }
        }
        .confirmationDialog(
            String(localized: "Turn off the Keepwell passcode?", bundle: #bundle),
            isPresented: $isConfirmingPasscodeOff,
            titleVisibility: .visible,
        ) {
            Button(role: .destructive) {
                Task { await viewModel.turnOffPasscode() }
            } label: {
                Text("Turn off passcode", bundle: #bundle)
            }
        } message: {
            Text("Keepwell will ask for your iPhone passcode instead.", bundle: #bundle)
        }
    }

    private var unlockPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            KWSettingsRow(
                String(localized: "Unlock the app with", bundle: #bundle),
                description: String(localized: "We use Face ID or Touch ID, whichever your iPhone has", bundle: #bundle),
                icon: .faceID,
                tint: KWSettingsTint.security,
            )
            .padding(.bottom, -KWSpacing.xs)
            HStack(spacing: 6) {
                ForEach(UnlockMethod.allCases, id: \.self) { method in
                    unlockOption(method, isSelected: settings.unlockMethod == method)
                }
            }
            .accessibilityElement(children: .contain)
            .padding(.bottom, 14)
        }
    }

    private var hideAmountsToggle: some View {
        KWSettingsRow(
            String(localized: "Hide amounts when leaving", bundle: #bundle),
            icon: .eyeOff,
            tint: KWSettingsTint.security,
        ) {
            // The row's title is the label; the style would draw a second one.
            Toggle(
                isOn: Binding(
                    get: { settings.hidesAmountsInAppSwitcher },
                    set: { hides in Task { await viewModel.setHidesAmounts(hides) } },
                ),
            ) { EmptyView() }
                .accessibilityLabel(Text("Hide amounts when leaving", bundle: #bundle))
                .toggleStyle(.kw)
        }
    }

    /// The app's own six-digit code: the keypad on the lock screen, with Face ID on top.
    @ViewBuilder
    private var passcodeRow: some View {
        let title = String(localized: "Keepwell passcode", bundle: #bundle)
        if overview.hasPasscode {
            Menu {
                Button { onSetUpPasscode() } label: {
                    Text("Change passcode", bundle: #bundle)
                }
                Button(role: .destructive) { isConfirmingPasscodeOff = true } label: {
                    Text("Turn off passcode", bundle: #bundle)
                }
            } label: {
                KWSettingsRow(
                    title, icon: .key, tint: KWSettingsTint.security,
                    value: String(localized: "On", bundle: #bundle), accessory: .chevron,
                )
            }
            .buttonStyle(.plain)
        } else {
            Button(action: onSetUpPasscode) {
                KWSettingsRow(
                    title,
                    description: String(
                        localized: "Six digits, kept only on this iPhone. Without one, the lock uses your iPhone passcode.",
                        bundle: #bundle,
                    ),
                    icon: .key,
                    tint: KWSettingsTint.security,
                    value: String(localized: "Set up", bundle: #bundle),
                    accessory: .chevron,
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func unlockOption(_ method: UnlockMethod, isSelected: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return Button {
            Task { await viewModel.setUnlockMethod(method) }
        } label: {
            Text(viewModel.unlockTitle(method))
                .font(.kw(12, weight: 600, relativeTo: .caption))
                .multilineTextAlignment(.center)
                .lineSpacing(1)
                .foregroundStyle(isSelected ? KWColor.Semantic.primaryForeground : KWColor.Text.secondary)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 56)
                .padding(.vertical, KWSpacing.xxs)
                .background(isSelected ? KWColor.Semantic.primary : KWColor.Surface.surface2, in: shape)
                .overlay { shape.strokeBorder(isSelected ? KWColor.Semantic.primary : KWColor.Surface.border) }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// Sync with the Keepwell account when there is one, then the CSV export and import: the way to
/// keep a copy or move movements by hand.
struct DataSection: View {
    let viewModel: SettingsViewModel
    let syncRow: AnyView?
    @State private var isImporting = false

    var body: some View {
        SettingsSection(title: String(localized: "Data & sync", bundle: #bundle)) {
            KWGroupedCard {
                if let syncRow {
                    syncRow
                }
                Button { isImporting = true } label: {
                    KWSettingsRow(
                        String(localized: "Import CSV", bundle: #bundle),
                        description: String(localized: "Add movements from a spreadsheet", bundle: #bundle),
                        icon: .download,
                        tint: KWSettingsTint.data,
                        accessory: .chevron,
                    )
                }
                .disabled(viewModel.isWorking)
                Button {
                    Task { await viewModel.export() }
                } label: {
                    KWSettingsRow(
                        String(localized: "Export CSV", bundle: #bundle),
                        description: String(localized: "A copy of every movement", bundle: #bundle),
                        icon: .share,
                        tint: KWSettingsTint.data,
                        accessory: .chevron,
                    )
                }
                .disabled(viewModel.isWorking)
            }
            .buttonStyle(.plain)
            if let message = viewModel.importMessage {
                Text(message)
                    .font(KWTextStyle.caption.font.weight(.regular))
                    .foregroundStyle(KWColor.State.positive)
            }
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.commaSeparatedText, .plainText]) { result in
            if case let .success(url) = result {
                Task { await viewModel.importFile(at: url) }
            }
        }
    }
}
