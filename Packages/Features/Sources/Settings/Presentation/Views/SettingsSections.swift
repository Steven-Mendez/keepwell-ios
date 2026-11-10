import DesignSystem
import Domain
import SettingsDomain
import SwiftUI
import UniformTypeIdentifiers

/// A muted section title over its card.
struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            KWSectionHeader(title).padding(.top, KWSpacing.xs)
            content
        }
    }
}

/// A settings row whose value opens a menu of fixed choices.
struct SettingsMenuRow<Option: Hashable>: View {
    let label: String
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
            // One line each, as in the design: a long label shrinks a little rather than wrapping.
            HStack(spacing: KWSpacing.sm) {
                Text(label)
                    .foregroundStyle(KWColor.Text.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: KWSpacing.xs)
                Text("\(value) ›")
                    .font(.kw(15, weight: 600))
                    .foregroundStyle(KWColor.Text.primary)
                    .lineLimit(1)
                    .fixedSize()
            }
            .font(KWTextStyle.body.font)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
        }
        .buttonStyle(.plain)
    }
}

/// How the app unlocks, when it asks again and whether amounts hide in the app switcher.
struct SecuritySection: View {
    @Bindable var viewModel: SettingsViewModel
    let overview: SettingsOverview
    let onSetUpPasscode: () -> Void
    @State private var isConfirmingPasscodeOff = false
    @FocusState private var isEditingName: Bool

    private var settings: Settings {
        overview.settings
    }

    var body: some View {
        SettingsSection(title: String(localized: "Security and privacy", bundle: #bundle)) {
            KWGroupedCard {
                unlockPicker
                if settings.unlockMethod != .disabled {
                    passcodeRow
                    nameRow
                    SettingsMenuRow(
                        label: String(localized: "Ask again after", bundle: #bundle),
                        value: viewModel.relockTitle(settings.relockAfter),
                        options: SettingsViewModel.relockOptions,
                        title: viewModel.relockTitle,
                    ) { seconds in Task { await viewModel.setRelockAfter(seconds) } }
                }
                hideAmountsToggle
            }
        }
        .onChange(of: isEditingName) { _, editing in
            if !editing {
                Task { await viewModel.commitName() }
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
            VStack(alignment: .leading, spacing: 2) {
                Text("Unlock the app with", bundle: #bundle).font(KWTextStyle.body.font)
                Text("We use Face ID or Touch ID, whichever your iPhone has", bundle: #bundle)
                    .font(KWTextStyle.captionSm.font.weight(.regular))
                    .foregroundStyle(KWColor.Text.muted)
            }
            HStack(spacing: 6) {
                ForEach(UnlockMethod.allCases, id: \.self) { method in
                    unlockOption(method, isSelected: settings.unlockMethod == method)
                }
            }
            .accessibilityElement(children: .contain)
        }
        .padding(.vertical, 14)
    }

    private var hideAmountsToggle: some View {
        Toggle(isOn: Binding(
            get: { settings.hidesAmountsInAppSwitcher },
            set: { hides in Task { await viewModel.setHidesAmounts(hides) } },
        )) {
            Text("Hide amounts when leaving", bundle: #bundle).font(KWTextStyle.body.font)
        }
        .toggleStyle(.kw)
        .padding(.vertical, 14)
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
                KWValueRow(title, value: String(localized: "On ›", bundle: #bundle), style: .navigation, verticalPadding: 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            Button(action: onSetUpPasscode) {
                VStack(alignment: .leading, spacing: 2) {
                    KWValueRow(title, value: String(localized: "Set up ›", bundle: #bundle), style: .navigation, verticalPadding: 0)
                    Text("Six digits, kept only on this iPhone. Without one, the lock uses your iPhone passcode.", bundle: #bundle)
                        .font(KWTextStyle.captionSm.font.weight(.regular))
                        .foregroundStyle(KWColor.Text.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    /// The name the lock screen greets with ("Good morning, Steven").
    private var nameRow: some View {
        HStack(spacing: KWSpacing.sm) {
            Text("Your name", bundle: #bundle).font(KWTextStyle.body.font)
            Spacer(minLength: KWSpacing.xs)
            TextField(String(localized: "For the greeting", bundle: #bundle), text: $viewModel.nameText)
                .multilineTextAlignment(.trailing)
                .font(.kw(15, weight: 600))
                .textContentType(.givenName)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused($isEditingName)
                .padding(.vertical, KWSpacing.xs)
                .padding(.horizontal, 10)
                .frame(maxWidth: 170)
                .background(KWColor.Surface.surface2, in: RoundedRectangle(cornerRadius: 10))
        }
        .padding(.vertical, 10)
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
                .foregroundStyle(isSelected ? Color.black : KWColor.Text.secondary)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(isSelected ? Color.white : KWColor.Surface.surface2, in: shape)
                .overlay { shape.strokeBorder(isSelected ? Color.white : KWColor.Surface.border) }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// The CSV export and import: the one way to keep a copy or move movements by hand. Syncing with
/// other devices is the Keepwell account's job (Account).
struct DataSection: View {
    let viewModel: SettingsViewModel
    let overview: SettingsOverview
    @State private var isImporting = false

    var body: some View {
        SettingsSection(title: String(localized: "Data", bundle: #bundle)) {
            KWGroupedCard {
                csvRows
            }
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

    @ViewBuilder
    private var csvRows: some View {
        Button { isImporting = true } label: {
            KWValueRow(String(localized: "Import CSV", bundle: #bundle), value: "›", style: .navigation, verticalPadding: 14)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isWorking)
        Button {
            Task { await viewModel.export() }
        } label: {
            KWValueRow(String(localized: "Export CSV", bundle: #bundle), value: "›", style: .navigation, verticalPadding: 14)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isWorking)
    }
}
