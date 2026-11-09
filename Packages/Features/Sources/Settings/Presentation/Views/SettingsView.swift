import DesignSystem
import Domain
import SettingsDomain
import SwiftUI
import UIKit

/// Settings: currency and rate, card reminders, organization counts, lock and privacy,
/// backup, CSV export and deleting everything.
public struct SettingsView: View {
    @Bindable private var viewModel: SettingsViewModel
    private let onBack: () -> Void
    private let onErased: () -> Void
    private let onSetUpPasscode: () -> Void
    private let onOpenCategories: (TransactionKind) -> Void
    private let onOpenPaymentMethods: () -> Void
    private let onOpenRecurring: () -> Void
    private let onOpenRules: () -> Void
    /// The Keepwell account section, owned by `CloudAccountPresentation`; absent in builds without an API.
    private let accountSection: AnyView?
    @State private var isConfirmingErase = false
    @State private var isConfirmingSwap = false
    @FocusState private var isEditingRate: Bool
    @Environment(\.openURL) private var openURL

    /// `onSetUpPasscode` opens creating or changing the app passcode, which the lock feature owns.
    public init(
        viewModel: SettingsViewModel,
        onBack: @escaping () -> Void,
        onErased: @escaping () -> Void,
        onSetUpPasscode: @escaping () -> Void = {},
        onOpenCategories: @escaping (TransactionKind) -> Void = { _ in },
        onOpenPaymentMethods: @escaping () -> Void = {},
        onOpenRecurring: @escaping () -> Void = {},
        onOpenRules: @escaping () -> Void = {},
        accountSection: AnyView? = nil,
    ) {
        self.accountSection = accountSection
        self.viewModel = viewModel
        self.onBack = onBack
        self.onErased = onErased
        self.onSetUpPasscode = onSetUpPasscode
        self.onOpenCategories = onOpenCategories
        self.onOpenPaymentMethods = onOpenPaymentMethods
        self.onOpenRecurring = onOpenRecurring
        self.onOpenRules = onOpenRules
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                KWNavigationHeader(String(localized: "Settings", bundle: #bundle), style: .large, onBack: onBack)
                    .padding(.bottom, KWSpacing.xs)
                if let overview = viewModel.overview {
                    sections(overview)
                }
                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(KWTextStyle.caption.font)
                        .foregroundStyle(KWColor.State.negative)
                }
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
        .onChange(of: isEditingRate) { _, editing in
            if !editing {
                Task { await viewModel.commitRate() }
            }
        }
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
            Text(
                // swiftlint:disable:next line_length
                "Your accounts, cards and transactions are deleted from this iPhone. This can't be undone. Data synced to your Keepwell account goes when you delete the account.",
                bundle: #bundle,
            )
        }
    }

    // MARK: - Sections

    private func currency(_ settings: Settings) -> some View {
        SettingsSection(title: String(localized: "Currency", bundle: #bundle)) {
            KWGroupedCard {
                currencyRow(String(localized: "Main currency", bundle: #bundle), code: settings.currencies.principal)
                if let second = settings.currencies.second {
                    currencyRow(String(localized: "Second currency", bundle: #bundle), code: second)
                    Button { isConfirmingSwap = true } label: {
                        KWValueRow(
                            String(localized: "Make \(second) the main currency", bundle: #bundle),
                            value: "⇅",
                            style: .navigation,
                            verticalPadding: 14,
                        )
                        .contentShape(Rectangle())
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
                    rateRow(settings.currencies)
                    Text(viewModel.rateFootnote)
                        .font(KWTextStyle.captionSm.font.weight(.regular))
                        .foregroundStyle(KWColor.Text.muted)
                        .lineSpacing(3)
                        .padding(.top, KWSpacing.sm)
                        .padding(.bottom, 14)
                }
            }
        }
    }

    /// One line, as in the design: long currency names shrink a little instead of wrapping.
    private func currencyRow(_ label: String, code: String) -> some View {
        HStack(spacing: KWSpacing.sm) {
            Text(label)
            Spacer(minLength: KWSpacing.xs)
            Text(viewModel.currencyName(code))
                .font(.kw(15, weight: 600))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .font(KWTextStyle.body.font)
        .padding(.vertical, 14)
        .accessibilityElement(children: .combine)
    }

    /// Keepwell follows the iPhone's language. iOS also lets each app use its own, from the app's
    /// page in the iPhone's Settings, and reopens the app in it; the row leads there.
    private var languageSection: some View {
        SettingsSection(title: String(localized: "Language", bundle: #bundle)) {
            KWGroupedCard {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                } label: {
                    KWValueRow(
                        String(localized: "App language", bundle: #bundle),
                        value: "\(viewModel.languageName) ›",
                        style: .setting,
                        verticalPadding: 14,
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Text("Keepwell uses your iPhone's language. To use another one only here, choose it in iPhone Settings.", bundle: #bundle)
                    .font(KWTextStyle.captionSm.font.weight(.regular))
                    .foregroundStyle(KWColor.Text.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, KWSpacing.sm)
            }
        }
    }

    private func rateRow(_ currencies: CurrencySettings) -> some View {
        HStack(spacing: KWSpacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "1 \(currencies.principal) =").font(KWTextStyle.body.font)
                Text("Manual · default 1", bundle: #bundle)
                    .font(KWTextStyle.captionSm.font.weight(.regular))
                    .foregroundStyle(KWColor.Text.muted)
            }
            Spacer(minLength: KWSpacing.xs)
            TextField(String(localized: "Rate", bundle: #bundle), text: $viewModel.rateText)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(.kw(15, weight: 600))
                .monospacedDigit()
                .focused($isEditingRate)
                .padding(.vertical, KWSpacing.xs)
                .padding(.horizontal, 10)
                .frame(width: 100)
                .background(KWColor.Surface.surface2, in: RoundedRectangle(cornerRadius: 10))
            Text(currencies.second ?? "").font(.kw(15, weight: 600))
        }
        .padding(.vertical, 14)
    }

    private func cards(_ settings: Settings) -> some View {
        SettingsSection(title: String(localized: "Credit cards", bundle: #bundle)) {
            KWGroupedCard {
                SettingsMenuRow(
                    label: String(localized: "Remind me to pay", bundle: #bundle),
                    value: viewModel.reminderTitle(settings.paymentReminderDaysBefore),
                    options: SettingsViewModel.reminderOptions,
                    title: viewModel.reminderTitle,
                ) { days in Task { await viewModel.setReminderDays(days) } }
            }
        }
    }

    private func organization(_ overview: SettingsOverview) -> some View {
        SettingsSection(title: String(localized: "Organization", bundle: #bundle)) {
            KWGroupedCard {
                categoriesRow(
                    String(localized: "Expense categories", bundle: #bundle),
                    count: overview.expenseCategoryCount,
                    kind: .expense,
                )
                categoriesRow(String(localized: "Income categories", bundle: #bundle), count: overview.incomeCategoryCount, kind: .income)
                Button(action: onOpenPaymentMethods) {
                    KWValueRow(
                        String(localized: "Payment methods", bundle: #bundle),
                        value: "\(overview.paymentMethodCount) ›",
                        style: .navigation,
                        verticalPadding: 14,
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Button(action: onOpenRecurring) {
                    KWValueRow(String(localized: "Recurring", bundle: #bundle), value: "›", style: .navigation, verticalPadding: 14)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Button(action: onOpenRules) {
                    KWValueRow(String(localized: "Rules", bundle: #bundle), value: "›", style: .navigation, verticalPadding: 14)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func categoriesRow(_ label: String, count: Int, kind: TransactionKind) -> some View {
        Button { onOpenCategories(kind) } label: {
            KWValueRow(label, value: "\(count) ›", style: .navigation, verticalPadding: 14)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var erase: some View {
        VStack(spacing: KWSpacing.sm) {
            Button { isConfirmingErase = true } label: {
                Text("Delete all my data", bundle: #bundle)
            }
            .buttonStyle(.kw(.destructive, size: .row))
            .disabled(viewModel.isWorking)
            Text("Deletes the data on this iPhone.", bundle: #bundle)
                .font(KWTextStyle.captionSm.font.weight(.regular))
                .foregroundStyle(KWColor.Text.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .padding(.top, KWSpacing.sm)
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

extension SettingsView {
    @ViewBuilder
    private func sections(_ overview: SettingsOverview) -> some View {
        if let accountSection {
            accountSection
        }
        currency(overview.settings)
        cards(overview.settings)
        organization(overview)
        languageSection
        SecuritySection(viewModel: viewModel, overview: overview, onSetUpPasscode: onSetUpPasscode)
        DataSection(viewModel: viewModel, overview: overview)
        erase
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
