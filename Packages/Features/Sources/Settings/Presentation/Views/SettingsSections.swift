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
    var description: String?
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
            KWSettingsRow(label, description: description, icon: icon, tint: tint, value: value, accessory: .chevron)
        }
        .buttonStyle(.plain)
    }
}

/// Who the app greets and in which language.
struct ProfileSection: View {
    @Bindable var viewModel: SettingsViewModel
    let onShowKeyboardShortcuts: () -> Void
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
                Button(action: onShowKeyboardShortcuts) {
                    KWSettingsRow(
                        String(localized: "Keyboard shortcuts", bundle: #bundle),
                        icon: .list,
                        tint: KWSettingsTint.profile,
                        value: "?",
                        accessory: .chevron,
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
        KWSettingsRow(
            String(localized: "Your name", bundle: #bundle),
            description: String(localized: "For the greeting", bundle: #bundle),
            icon: .person,
            tint: KWSettingsTint.profile,
        ) {
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
