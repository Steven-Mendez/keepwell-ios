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
    let viewModel: SettingsViewModel
    let settings: Settings

    var body: some View {
        SettingsSection(title: String(localized: "Security and privacy", bundle: #bundle)) {
            KWGroupedCard {
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
                if settings.unlockMethod != .disabled {
                    SettingsMenuRow(
                        label: String(localized: "Ask again after", bundle: #bundle),
                        value: viewModel.relockTitle(settings.relockAfter),
                        options: SettingsViewModel.relockOptions,
                        title: viewModel.relockTitle,
                    ) { seconds in Task { await viewModel.setRelockAfter(seconds) } }
                }
                Toggle(isOn: Binding(
                    get: { settings.hidesAmountsInAppSwitcher },
                    set: { hides in Task { await viewModel.setHidesAmounts(hides) } },
                )) {
                    Text("Hide amounts when leaving", bundle: #bundle).font(KWTextStyle.body.font)
                }
                .toggleStyle(.kw)
                .padding(.vertical, 14)
            }
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

/// iCloud backup and CSV export.
struct DataSection: View {
    let viewModel: SettingsViewModel
    let overview: SettingsOverview
    @State private var isImporting = false
    @State private var isPickingBackup = false
    @State private var pendingRestore: URL?

    var body: some View {
        SettingsSection(title: String(localized: "Data", bundle: #bundle)) {
            KWGroupedCard {
                VStack(alignment: .leading, spacing: 10) {
                    backupToggle
                    HStack(spacing: 6) {
                        Circle()
                            .fill(overview.isICloudBackupEnabled ? KWColor.State.positive : KWColor.Text.faint)
                            .frame(width: 8, height: 8)
                        Text(backupStatus)
                            .font(KWTextStyle.caption.font.weight(.regular))
                            .foregroundStyle(KWColor.Text.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.leading, 52)
                    if overview.isICloudBackupEnabled {
                        backupActions
                    }
                }
                .padding(.vertical, 14)
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
        .background {
            // A second importer can't share a view with the first, so it lives on the background.
            Color.clear.fileImporter(isPresented: $isPickingBackup, allowedContentTypes: [.json]) { result in
                if case let .success(url) = result {
                    pendingRestore = url
                }
            }
        }
        .confirmationDialog(
            String(localized: "Replace your data with this backup?", bundle: #bundle),
            isPresented: Binding(get: { pendingRestore != nil }, set: {
                if !$0 {
                    pendingRestore = nil
                }
            }),
            titleVisibility: .visible,
        ) {
            Button(role: .destructive) {
                if let url = pendingRestore {
                    Task { _ = await viewModel.restore(from: url) }
                }
            } label: {
                Text("Restore", bundle: #bundle)
            }
        } message: {
            Text("What's on this iPhone now is replaced by the backup.", bundle: #bundle)
        }
    }

    private var backupActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: KWSpacing.xs) {
                Button {
                    Task { await viewModel.backUpNow() }
                } label: {
                    Text("Back up now", bundle: #bundle)
                }
                .buttonStyle(.kw(.primary, size: .small))
                Button { isPickingBackup = true } label: {
                    Text("Restore", bundle: #bundle)
                }
                .buttonStyle(.kw(.secondary, size: .small))
            }
            .disabled(viewModel.isWorking)
            if let message = viewModel.backupMessage {
                Text(message)
                    .font(KWTextStyle.captionSm.font.weight(.regular))
                    .foregroundStyle(KWColor.Text.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.leading, 52)
    }

    private var backupToggle: some View {
        Toggle(isOn: Binding(
            get: { overview.isICloudBackupEnabled },
            set: { enabled in Task { await viewModel.setICloudBackup(enabled) } },
        )) {
            HStack(spacing: KWSpacing.sm) {
                KWIconView(.cloud, size: 20)
                    .foregroundStyle(KWColor.Brand.link)
                    .frame(width: 40, height: 40)
                    .background(KWColor.Tint.accent, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("iCloud backup", bundle: #bundle).font(KWTextStyle.body.font)
                    Text("In your own iCloud, encrypted. We don't see anything.", bundle: #bundle)
                        .font(KWTextStyle.captionSm.font.weight(.regular))
                        .foregroundStyle(KWColor.Text.muted)
                }
            }
        }
        .toggleStyle(.kw)
    }

    private var backupStatus: String {
        if viewModel.backupChangeIsPending {
            return String(localized: "The change applies the next time you open Keepwell.", bundle: #bundle)
        }
        if overview.isICloudBackupEnabled, let last = overview.lastBackupDate {
            let when = last.formatted(.relative(presentation: .named))
            return String(localized: "Last backup: \(when)", bundle: #bundle)
        }
        return overview.isICloudBackupEnabled
            ? String(localized: "Syncs on its own while you have iCloud on this iPhone.", bundle: #bundle)
            : String(localized: "Off: your data stays only on this iPhone.", bundle: #bundle)
    }
}
