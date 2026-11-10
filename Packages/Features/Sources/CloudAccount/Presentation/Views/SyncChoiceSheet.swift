import CloudAccountDomain
import DesignSystem
import SwiftUI

/// The first sync with an account found data on this iPhone and in the account. Mixing them would
/// duplicate whatever was entered on both, so the person keeps one side and the other is replaced.
/// keepwell-web asks the same question with the same words.
public struct SyncChoiceSheet: View {
    private let sync: SyncCoordinator
    private let conflict: SyncConflict
    @State private var isConfirmingReplace = false
    @State private var failed = false

    public init(sync: SyncCoordinator, conflict: SyncConflict) {
        self.sync = sync
        self.conflict = conflict
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KWSpacing.lg) {
                heading
                VStack(spacing: KWSpacing.sm) {
                    OptionCard(
                        option: SyncOption(
                            title: String(localized: "Use your account's data", bundle: #bundle),
                            detail: String(
                                localized: "Replaces what's on this iPhone with the data in your Keepwell account.",
                                bundle: #bundle,
                            ),
                            icon: .cloud,
                            tint: KWSettingsTint.account,
                        ),
                        summary: conflict.account,
                    ) { choose(.useAccount) }
                    OptionCard(
                        option: SyncOption(
                            title: String(localized: "Keep this iPhone's data", bundle: #bundle),
                            detail: Self.keepDeviceDetail,
                            icon: .phone,
                            tint: KWSettingsTint.money,
                        ),
                        summary: conflict.device,
                    ) { isConfirmingReplace = true }
                }
                .disabled(sync.isResolving)
                footer
            }
            .padding(.horizontal, KWLayout.gutter)
            .padding(.top, KWSpacing.xl)
            .padding(.bottom, KWSpacing.lg)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(KWColor.Surface.bg)
        .foregroundStyle(KWColor.Text.primary)
        .interactiveDismissDisabled(sync.isResolving)
        .confirmationDialog(
            String(localized: "Replace your account's data?", bundle: #bundle),
            isPresented: $isConfirmingReplace,
            titleVisibility: .visible,
        ) {
            Button(role: .destructive) { choose(.keepDevice) } label: {
                Text("Replace", bundle: #bundle)
            }
        } message: {
            Text(Self.keepDeviceDetail)
        }
    }

    private static var keepDeviceDetail: String {
        String(localized: "Replaces your account's data, on every device, with what's here.", bundle: #bundle)
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: KWSpacing.xs) {
            Text("This iPhone and your account have different data", bundle: #bundle)
                .font(KWTextStyle.titleSm.font)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text("Choose which to keep. The other is replaced, and this can't be undone.", bundle: #bundle)
                .font(KWTextStyle.body.font)
                .foregroundStyle(KWColor.Text.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var footer: some View {
        if failed {
            Text("Couldn't reach Keepwell. Try again.", bundle: #bundle)
                .font(KWTextStyle.caption.font)
                .foregroundStyle(KWColor.State.negative)
        }
        if sync.isResolving {
            ProgressView().frame(maxWidth: .infinity, minHeight: KWLayout.minTouch)
        } else {
            Button { sync.decideLater() } label: {
                Text("Decide later", bundle: #bundle)
            }
            .buttonStyle(.kw(.plain, size: .text))
            .frame(maxWidth: .infinity)
        }
    }

    private func choose(_ choice: SyncChoice) {
        failed = false
        Task {
            failed = await !sync.resolve(choice)
        }
    }

    /// "12 movements · 3 accounts", then recurring, goals, debts (loans included) and rules when there
    /// are any, as keepwell-web counts them. Cards come with accounts, so they aren't counted.
    static func counts(_ summary: SyncDataSummary) -> String {
        var parts = [
            String(localized: "\(summary.movements) movements", bundle: #bundle),
            String(localized: "\(summary.accounts) accounts", bundle: #bundle),
        ]
        if summary.recurring > 0 {
            parts.append(String(localized: "\(summary.recurring) recurring", bundle: #bundle))
        }
        if summary.goals > 0 {
            parts.append(String(localized: "\(summary.goals) goals", bundle: #bundle))
        }
        if summary.loans + summary.debts > 0 {
            parts.append(String(localized: "\(summary.loans + summary.debts) debts", bundle: #bundle))
        }
        if summary.rules > 0 {
            parts.append(String(localized: "\(summary.rules) rules", bundle: #bundle))
        }
        // Each count stays on one line: "4 recurring" never splits across two.
        return parts.map { $0.replacingOccurrences(of: " ", with: "\u{00A0}") }.joined(separator: " · ")
    }
}

private struct SyncOption {
    let title: String
    let detail: String
    let icon: KWIcon
    let tint: Color
}

/// One side of the choice: what keeping it does, and how much it holds.
private struct OptionCard: View {
    let option: SyncOption
    let summary: SyncDataSummary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: KWSpacing.sm) {
                KWSettingsIcon(option.icon, tint: option.tint)
                VStack(alignment: .leading, spacing: KWSpacing.xxs) {
                    Text(option.title)
                        .font(KWTextStyle.heading.font)
                    Text(option.detail)
                        .font(KWTextStyle.caption.font)
                        .foregroundStyle(KWColor.Text.muted)
                    Text(SyncChoiceSheet.counts(summary))
                        .font(KWTextStyle.label.font)
                        .foregroundStyle(KWColor.Text.secondary)
                        .padding(.top, 2)
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                KWIconView(.chevronRight, size: 16, lineWidth: 2.4)
                    .foregroundStyle(KWColor.Text.faint)
                    .frame(maxHeight: .infinity)
            }
            .padding(KWSpacing.md)
            .background(KWColor.Surface.surface, in: RoundedRectangle(cornerRadius: KWRadius.surface, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}
