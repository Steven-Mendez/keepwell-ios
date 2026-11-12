import DesignSystem
import Domain
import SettingsDomain
import SwiftUI
import UIKit

/// The pieces of Settings that belong to the Keepwell account, built by `CloudAccountPresentation`
/// and left out in builds without an API. Each piece hides itself when it doesn't apply.
public struct SettingsAccountViews {
    /// The profile card at the top: who is signed in and how sync is doing, or the sign-in.
    let header: AnyView
    /// The sync row at the top of Data. It always shows one row.
    let syncRow: AnyView
    /// Connected assistants and supporting Keepwell, between Security and About.
    let sections: AnyView
    /// Signing out and deleting the account, at the bottom with the other destructive rows.
    let destructiveRows: AnyView
    /// Whether a Keepwell account is signed in: erasing this iPhone then signs out too, and the
    /// confirmation says so.
    let isSignedIn: Bool

    public init(header: AnyView, syncRow: AnyView, sections: AnyView, destructiveRows: AnyView, isSignedIn: Bool = false) {
        self.header = header
        self.syncRow = syncRow
        self.sections = sections
        self.destructiveRows = destructiveRows
        self.isSignedIn = isSignedIn
    }
}

/// Settings, in keepwell-web's order and names: the account, Profile & preferences, Money,
/// Organization, Data & sync, Security, Connected assistants, About, then the destructive rows.
/// Support Keepwell (the App Store coffee) is iOS only and sits before About.
public struct SettingsView: View {
    @Bindable private var viewModel: SettingsViewModel
    private let onBack: () -> Void
    private let onErased: () -> Void
    private let onSetUpPasscode: () -> Void
    private let onOpenCategories: (TransactionKind) -> Void
    private let onOpenPaymentMethods: () -> Void
    private let onOpenRules: () -> Void
    private let onShowKeyboardShortcuts: () -> Void
    private let account: SettingsAccountViews?
    private let about: SettingsAbout
    @State private var isConfirmingErase = false

    /// `onSetUpPasscode` opens creating or changing the app passcode, which the lock feature owns.
    public init(
        viewModel: SettingsViewModel,
        onBack: @escaping () -> Void,
        onErased: @escaping () -> Void,
        onSetUpPasscode: @escaping () -> Void = {},
        onOpenCategories: @escaping (TransactionKind) -> Void = { _ in },
        onOpenPaymentMethods: @escaping () -> Void = {},
        onOpenRules: @escaping () -> Void = {},
        onShowKeyboardShortcuts: @escaping () -> Void = {},
        account: SettingsAccountViews? = nil,
        about: SettingsAbout = SettingsAbout(),
    ) {
        self.account = account
        self.about = about
        self.viewModel = viewModel
        self.onBack = onBack
        self.onErased = onErased
        self.onSetUpPasscode = onSetUpPasscode
        self.onOpenCategories = onOpenCategories
        self.onOpenPaymentMethods = onOpenPaymentMethods
        self.onOpenRules = onOpenRules
        self.onShowKeyboardShortcuts = onShowKeyboardShortcuts
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KWSpacing.lg) {
                KWNavigationHeader(String(localized: "Settings", bundle: #bundle), style: .large, onBack: onBack)
                if let account {
                    account.header
                } else {
                    LocalProfileHeader(name: viewModel.overview?.preferredName)
                }
                if let overview = viewModel.overview {
                    sections(overview)
                }
                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(KWTextStyle.caption.font)
                        .foregroundStyle(KWColor.State.negative)
                } else if let notice = viewModel.noticeMessage {
                    Text(notice)
                        .font(KWTextStyle.caption.font)
                        .foregroundStyle(KWColor.Text.secondary)
                }
                AboutFooter(about: about)
            }
            .padding(.horizontal, KWLayout.gutter)
            .padding(.top, KWLayout.safeTop)
            .padding(.bottom, KWSpacing.xxl)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.immediately)
        .ignoresSafeArea(edges: .top)
        .background(KWColor.Surface.bg)
        .foregroundStyle(KWColor.Text.primary)
        .toolbar(.hidden, for: .navigationBar)
        .task { await viewModel.load() }
        .sheet(item: $viewModel.exportedFile) { file in
            ShareSheet(items: [file.url])
                .presentationDetents([.medium, .large])
        }
        .confirmationDialog(
            String(localized: "Delete all your data?", bundle: #bundle),
            isPresented: $isConfirmingErase,
            titleVisibility: .visible,
        ) {
            eraseConfirmation
        } message: {
            Text(eraseMessage)
        }
    }

    private var eraseMessage: String {
        let base = String(
            // swiftlint:disable:next line_length
            localized: "Your accounts, cards and transactions are deleted from this iPhone. This can't be undone. Data synced to your Keepwell account goes when you delete the account.",
            bundle: #bundle,
        )
        guard account?.isSignedIn == true else { return base }
        return [
            base,
            String(localized: "Your Keepwell account keeps its copy; to erase it too, delete your account.", bundle: #bundle),
            String(localized: "You'll be signed out on this iPhone.", bundle: #bundle),
        ].joined(separator: " ")
    }

    @ViewBuilder
    private func sections(_ overview: SettingsOverview) -> some View {
        ProfileSection(viewModel: viewModel, onShowKeyboardShortcuts: onShowKeyboardShortcuts)
        MoneySection(viewModel: viewModel, overview: overview)
        organization(overview)
        DataSection(viewModel: viewModel, syncRow: account?.syncRow)
        SecuritySection(viewModel: viewModel, overview: overview, onSetUpPasscode: onSetUpPasscode)
        account?.sections
        AboutSection(about: about)
        destructive
    }

    private func organization(_ overview: SettingsOverview) -> some View {
        SettingsSection(title: String(localized: "Organization", bundle: #bundle)) {
            KWGroupedCard {
                Button { onOpenCategories(.expense) } label: {
                    countRow(
                        String(localized: "Expense categories", bundle: #bundle),
                        .tag,
                        KWSettingsTint.organization,
                        overview.expenseCategoryCount,
                    )
                }
                Button { onOpenCategories(.income) } label: {
                    countRow(
                        String(localized: "Income categories", bundle: #bundle),
                        .tag,
                        KWSettingsTint.money,
                        overview.incomeCategoryCount,
                    )
                }
                Button(action: onOpenPaymentMethods) {
                    countRow(
                        String(localized: "Payment methods", bundle: #bundle),
                        .creditCard,
                        KWSettingsTint.data,
                        overview.paymentMethodCount,
                    )
                }
                Button(action: onOpenRules) { rulesRow(count: overview.categorizationRuleCount) }
            }
            .buttonStyle(.plain)
        }
    }

    private func rulesRow(count: Int) -> some View {
        KWSettingsRow(
            String(localized: "Rules", bundle: #bundle),
            description: String(localized: "Categorize movements by their description", bundle: #bundle),
            icon: .list,
            tint: KWSettingsTint.security,
            value: "\(count)",
            accessory: .chevron,
        )
    }

    private func countRow(_ title: String, _ icon: KWIcon, _ tint: Color, _ count: Int) -> some View {
        KWSettingsRow(title, icon: icon, tint: tint, value: "\(count)", accessory: .chevron)
    }

    /// Everything that can't be undone, apart and in red: the account's rows, then this iPhone's.
    private var destructive: some View {
        VStack(alignment: .leading, spacing: KWSpacing.sm) {
            account?.destructiveRows
            KWGroupedCard {
                Button { isConfirmingErase = true } label: {
                    KWSettingsRow(
                        String(localized: "Delete all my data", bundle: #bundle),
                        description: String(localized: "Deletes the data on this iPhone.", bundle: #bundle),
                        icon: .trash,
                        isDestructive: true,
                    )
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isWorking)
            }
        }
        .padding(.top, KWSpacing.xs)
    }

    private var eraseConfirmation: some View {
        Button(role: .destructive) {
            Task {
                if await viewModel.eraseAll() {
                    onErased()
                }
            }
        } label: {
            Text("Delete everything", bundle: #bundle)
        }
    }
}

/// What the About section and the footer show; the app passes its own version and links.
public struct SettingsAbout: Sendable {
    let version: String?
    let privacyPolicy: URL?

    public init(version: String? = nil, privacyPolicy: URL? = nil) {
        self.version = version
        self.privacyPolicy = privacyPolicy
    }
}

/// The header of a build without the Keepwell API: the person and where their data lives.
private struct LocalProfileHeader: View {
    let name: String?

    var body: some View {
        KWGroupedCard {
            HStack(spacing: KWSpacing.sm) {
                KWAvatar(name: name)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: name ?? "Keepwell")
                        .font(KWTextStyle.heading.font)
                    Text("Your data stays only on this iPhone.", bundle: #bundle)
                        .font(KWTextStyle.caption.font)
                        .foregroundStyle(KWColor.Text.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, KWSpacing.md)
        }
    }
}

private struct AboutSection: View {
    let about: SettingsAbout
    @Environment(\.openURL) private var openURL

    var body: some View {
        if let url = about.privacyPolicy {
            SettingsSection(title: String(localized: "About", bundle: #bundle)) {
                KWGroupedCard {
                    Button { openURL(url) } label: {
                        KWSettingsRow(
                            String(localized: "Privacy policy", bundle: #bundle),
                            icon: .shield,
                            tint: KWSettingsTint.about,
                            accessory: .external,
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

/// The logo and version at the end of the list, as most finance apps close their settings.
private struct AboutFooter: View {
    let about: SettingsAbout

    var body: some View {
        VStack(spacing: KWSpacing.xs) {
            KWLogoMark(size: 28)
                .foregroundStyle(KWColor.Text.faint)
            if let version = about.version {
                Text("Keepwell \(version)", bundle: #bundle)
                    .font(KWTextStyle.captionSm.font)
                    .foregroundStyle(KWColor.Text.faint)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, KWSpacing.sm)
        .accessibilityElement(children: .combine)
    }
}

/// The system share sheet, for the exported file.
private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context _: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_: UIActivityViewController, context _: Context) {}
}
