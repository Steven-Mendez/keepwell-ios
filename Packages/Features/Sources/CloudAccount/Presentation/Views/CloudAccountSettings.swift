import CloudAccountDomain
import DesignSystem
import SwiftUI

// The Keepwell account's pieces of Settings. Settings places them (header at the top, the sync row
// in Data, assistants and support before About, the destructive rows at the bottom); each one
// hides itself when it doesn't apply.

/// The top of Settings: who is signed in, the plan and how sync is doing; or, while local-only,
/// a card that offers signing in to sync.
public struct CloudAccountHeader: View {
    @Bindable private var viewModel: CloudAccountViewModel
    @State private var showsInvitation = false
    @State private var passkeyAuthorizer = PasskeyAuthorizer()

    public init(viewModel: CloudAccountViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: KWSpacing.xs) {
            KWGroupedCard {
                content.padding(.vertical, KWSpacing.md)
            }
            if let error = viewModel.errorMessage {
                Text(error)
                    .font(KWTextStyle.caption.font)
                    .foregroundStyle(KWColor.State.negative)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, KWSpacing.xxs)
            }
        }
        .task { await viewModel.refresh() }
        .onChange(of: viewModel.needsInvitation) { _, needs in
            if needs {
                showsInvitation = true
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            ProgressView().frame(maxWidth: .infinity, minHeight: 52)
        case .signedOut:
            signIn
        case let .signedIn(user):
            profile(user)
        }
    }

    private func profile(_ user: CloudAccountUser) -> some View {
        HStack(alignment: .center, spacing: KWSpacing.sm) {
            KWAvatar(name: user.name.isEmpty ? user.email : user.name)
            VStack(alignment: .leading, spacing: 3) {
                Text(user.name.isEmpty ? user.email : user.name)
                    .font(KWTextStyle.heading.font)
                    .lineLimit(2)
                // Apple often shares no name, and the email shown twice reads as a glitch.
                if !user.name.isEmpty, user.name != user.email {
                    Text(user.email)
                        .font(KWTextStyle.caption.font)
                        .foregroundStyle(KWColor.Text.muted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                HStack(spacing: KWSpacing.xs) {
                    Text(planName(user))
                        .font(KWTextStyle.micro.font)
                        .foregroundStyle(KWColor.Brand.link)
                        .padding(.horizontal, KWSpacing.xs)
                        .padding(.vertical, 3)
                        .background(KWColor.Brand.link.opacity(0.14), in: Capsule())
                    SyncStatusLabel(status: SyncStatus(user: user, sync: viewModel.sync))
                }
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private func planName(_ user: CloudAccountUser) -> String {
        if !user.canBeSupported {
            return String(localized: "Supporter", bundle: #bundle)
        }
        if user.earlyAccess.contains("cloud_sync") {
            return String(localized: "Early access", bundle: #bundle)
        }
        return String(localized: "Free plan", bundle: #bundle)
    }

    private var signIn: some View {
        VStack(alignment: .leading, spacing: KWSpacing.sm) {
            HStack(alignment: .top, spacing: KWSpacing.sm) {
                KWSettingsIcon(.cloud, tint: KWSettingsTint.account)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sign in to sync", bundle: #bundle)
                        .font(KWTextStyle.heading.font)
                        .accessibilityAddTraits(.isHeader)
                    Text("Your data is only on this iPhone. Sign in to keep it in sync with Keepwell on the web.", bundle: #bundle)
                        .font(KWTextStyle.caption.font)
                        .foregroundStyle(KWColor.Text.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            AppleSignInButton(viewModel: viewModel)
                .frame(height: 50)
                .clipShape(Capsule())
                .padding(.top, KWSpacing.xxs)
            if viewModel.canUsePasskeys {
                Button {
                    Task { await viewModel.signInWithPasskey(using: passkeyAuthorizer) }
                } label: {
                    Text("Use a passkey", bundle: #bundle)
                }
                .buttonStyle(.kw(.secondary, size: .row))
                .disabled(viewModel.isWorking)
            }
            invitation
        }
    }

    /// Accounts are invite-only for new people, while everyone who already has one signs in
    /// without a code, so the field stays folded until asked for or the server wants one.
    @ViewBuilder
    private var invitation: some View {
        if showsInvitation {
            TextField(
                String(localized: "Invitation code (new accounts)", bundle: #bundle),
                text: $viewModel.invitation,
                prompt: Text("Invitation code (new accounts)", bundle: #bundle).foregroundStyle(KWColor.Text.faint),
            )
            .textInputAutocapitalization(.characters)
            .autocorrectionDisabled()
            .font(KWTextStyle.body.font.monospaced())
            .kwInputField()
        } else {
            Button { showsInvitation = true } label: {
                Text("Have an invitation code?", bundle: #bundle)
            }
            .buttonStyle(.kw(.plain, size: .text))
            .frame(maxWidth: .infinity)
        }
    }
}

/// The sync row at the top of Data: sync now, or reopen the choice while a conflict waits.
public struct CloudSyncRow: View {
    private let viewModel: CloudAccountViewModel

    public init(viewModel: CloudAccountViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        switch viewModel.state {
        case let .signedIn(user) where user.canSync:
            signedIn
        case .signedIn:
            KWSettingsRow(
                String(localized: "Sync", bundle: #bundle),
                description: String(
                    localized: "Sync isn't included in your plan. Everything keeps working on this iPhone.",
                    bundle: #bundle,
                ),
                icon: .refresh,
                tint: KWSettingsTint.account,
                value: String(localized: "Off", bundle: #bundle),
            )
        case .loading, .signedOut:
            KWSettingsRow(
                String(localized: "Sync", bundle: #bundle),
                description: String(localized: "Sign in at the top to sync with Keepwell on the web.", bundle: #bundle),
                icon: .refresh,
                tint: KWSettingsTint.account,
                value: String(localized: "Off", bundle: #bundle),
            )
        }
    }

    @ViewBuilder
    private var signedIn: some View {
        if let sync = viewModel.sync, sync.conflict != nil {
            Button { sync.reviewChoice() } label: {
                KWSettingsRow(
                    String(localized: "Choose which data to keep", bundle: #bundle),
                    description: String(localized: "Sync is paused until you choose.", bundle: #bundle),
                    icon: .refresh,
                    tint: KWColor.State.pending,
                    accessory: .chevron,
                )
            }
            .buttonStyle(.plain)
        } else {
            Button { viewModel.sync?.trigger(after: 0) } label: {
                KWSettingsRow(
                    String(localized: "Sync now", bundle: #bundle),
                    description: description,
                    icon: .refresh,
                    tint: KWSettingsTint.account,
                )
            }
            .buttonStyle(.plain)
            .disabled(viewModel.sync?.state == .syncing)
        }
    }

    private var description: String {
        switch viewModel.sync?.state {
        case .syncing:
            String(localized: "Syncing…", bundle: #bundle)
        case let .offline(pending) where pending > 0:
            String(localized: "Offline. Changes sync when you're back online.", bundle: #bundle)
        case .failed, .offline:
            String(localized: "Couldn't sync. Keepwell will try again.", bundle: #bundle)
        case let .idle(lastSync?, _):
            String(localized: "Last synced \(lastSync.formatted(.relative(presentation: .named)))", bundle: #bundle)
        default:
            String(localized: "Synced", bundle: #bundle)
        }
    }
}

/// Connected assistants and the coffee, each its own section, only when they apply.
public struct CloudAccountSections: View {
    private let viewModel: CloudAccountViewModel

    public init(viewModel: CloudAccountViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        if case let .signedIn(user) = viewModel.state {
            if user.capabilities.contains("mcp") {
                ConnectedAssistantsSection(viewModel: viewModel)
            }
            if user.canBeSupported, viewModel.canBuySupport {
                section(String(localized: "Support Keepwell", bundle: #bundle)) {
                    Button {
                        Task { await viewModel.buyCoffee() }
                    } label: {
                        KWSettingsRow(
                            String(localized: "Invite me a coffee", bundle: #bundle),
                            description: coffeeExplanation(user),
                            icon: .coffee,
                            tint: KWSettingsTint.reminders,
                            value: viewModel.coffeePrice,
                            accessory: .chevron,
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isWorking)
                    Button {
                        Task { await viewModel.restorePurchases() }
                    } label: {
                        KWSettingsRow(
                            String(localized: "Restore purchases", bundle: #bundle),
                            icon: .refresh,
                            tint: KWSettingsTint.about,
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isWorking)
                }
                if let message = viewModel.supportMessage {
                    Text(message)
                        .font(KWTextStyle.caption.font)
                        .foregroundStyle(KWColor.Text.secondary)
                        .padding(.horizontal, KWSpacing.xxs)
                }
            }
        }
    }

    private func section(_ title: String, @ViewBuilder rows: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: KWSpacing.xs) {
            KWSectionHeader(title).padding(.leading, KWSpacing.xxs)
            KWGroupedCard { rows() }
        }
    }

    private func coffeeExplanation(_ user: CloudAccountUser) -> String {
        if user.canSync, user.earlyAccess.contains("cloud_sync") {
            return String(
                // swiftlint:disable:next line_length
                localized: "Sync is included during early access. A one-time coffee keeps it, and lets Claude read and record your finances.",
                bundle: #bundle,
            )
        }
        return String(
            localized: "Sync with the web and Claude come with a one-time coffee. Everything else stays free and works on this iPhone.",
            bundle: #bundle,
        )
    }
}

/// Signing out here or everywhere, and deleting the account, in red at the bottom of Settings.
public struct CloudAccountDestructiveRows: View {
    private let viewModel: CloudAccountViewModel
    @State private var isConfirmingEverywhere = false
    @State private var isConfirmingDelete = false

    public init(viewModel: CloudAccountViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        if case .signedIn = viewModel.state {
            KWGroupedCard {
                Button {
                    Task { await viewModel.signOut(everywhere: false) }
                } label: {
                    KWSettingsRow(String(localized: "Sign out", bundle: #bundle), icon: .logOut, isDestructive: true)
                }
                Button { isConfirmingEverywhere = true } label: {
                    KWSettingsRow(
                        String(localized: "Sign out on all devices", bundle: #bundle),
                        description: String(localized: "Every iPhone and browser will need to sign in again.", bundle: #bundle),
                        icon: .logOut,
                        isDestructive: true,
                    )
                }
                Button { isConfirmingDelete = true } label: {
                    KWSettingsRow(
                        String(localized: "Delete account", bundle: #bundle),
                        description: String(localized: "Erases your synced data from Keepwell's servers.", bundle: #bundle),
                        icon: .trash,
                        isDestructive: true,
                    )
                }
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isWorking)
            .confirmationDialog(
                String(localized: "Sign out on all devices?", bundle: #bundle),
                isPresented: $isConfirmingEverywhere,
                titleVisibility: .visible,
            ) {
                Button(role: .destructive) {
                    Task { await viewModel.signOut(everywhere: true) }
                } label: {
                    Text("Sign out everywhere", bundle: #bundle)
                }
            } message: {
                Text("Every iPhone and browser signed in to this account will need to sign in again.", bundle: #bundle)
            }
            .confirmationDialog(
                String(localized: "Delete your Keepwell account?", bundle: #bundle),
                isPresented: $isConfirmingDelete,
                titleVisibility: .visible,
            ) {
                Button(role: .destructive) {
                    Task { await viewModel.deleteAccount() }
                } label: {
                    Text("Delete account", bundle: #bundle)
                }
            } message: {
                Text(
                    // swiftlint:disable:next line_length
                    "You're signed out everywhere at once and your synced data is erased from Keepwell's servers. Backups keep it up to 35 more days. What's on this iPhone stays here.",
                    bundle: #bundle,
                )
            }
        }
    }
}
