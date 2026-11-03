import DesignSystem
import SwiftUI

/// After "Start": whether there's a backup to bring. Restoring brings accounts, cards and movements
/// at once, so it's offered before any setup step rather than in the middle of one.
public struct ReturningView: View {
    private let restoreState: OnboardingViewModel.RestoreState
    private let onBack: () -> Void
    private let onRestoreFromICloud: () -> Void
    private let onRestoreFromFile: () -> Void
    private let onStartFresh: () -> Void

    public init(
        restoreState: OnboardingViewModel.RestoreState,
        onBack: @escaping () -> Void,
        onRestoreFromICloud: @escaping () -> Void,
        onRestoreFromFile: @escaping () -> Void,
        onStartFresh: @escaping () -> Void,
    ) {
        self.restoreState = restoreState
        self.onBack = onBack
        self.onRestoreFromICloud = onRestoreFromICloud
        self.onRestoreFromFile = onRestoreFromFile
        self.onStartFresh = onStartFresh
    }

    public var body: some View {
        KWScreen(bottom: 40) {
            VStack(alignment: .leading, spacing: KWSpacing.md) {
                KWFlowHeader(.back, action: onBack)
                OnboardingHeading(
                    title: String(localized: "Have you used Keepwell before?", bundle: #bundle),
                    message: String(
                        localized: "Bring your accounts, cards and movements from a backup, or set everything up from scratch.",
                        bundle: #bundle,
                    ),
                )
                KWGroupedCard {
                    option(
                        .cloud,
                        title: restoreState == .searching
                            ? String(localized: "Looking for your backup…", bundle: #bundle)
                            : String(localized: "Restore from iCloud", bundle: #bundle),
                        subtitle: String(localized: "If iCloud backup was on in Keepwell", bundle: #bundle),
                        action: onRestoreFromICloud,
                    )
                    .disabled(restoreState == .searching)
                    option(
                        .download,
                        title: String(localized: "Restore from a backup file (.json)", bundle: #bundle),
                        subtitle: String(localized: "A file saved with \u{201C}Back up now\u{201D} in Settings", bundle: #bundle),
                        action: onRestoreFromFile,
                    )
                }
                if restoreState == .notFound {
                    Text("We couldn't find a backup in your iCloud.", bundle: #bundle)
                        .font(KWTextStyle.caption.font)
                        .foregroundStyle(KWColor.Text.muted)
                }
                Spacer(minLength: 0)
                Button(action: onStartFresh) { Text("Start from scratch", bundle: #bundle) }
                    .buttonStyle(.kw())
            }
        }
    }

    private func option(_ icon: KWIcon, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: KWSpacing.sm) {
                KWIconView(icon, size: 18)
                    .frame(width: 36, height: 36)
                    .background(KWColor.Surface.surface2, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.kw(15, weight: 600))
                    Text(subtitle)
                        .font(KWTextStyle.captionSm.font.weight(.regular))
                        .foregroundStyle(KWColor.Text.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                KWIconView(.chevronRight, size: 16)
                    .foregroundStyle(KWColor.Text.faint)
            }
            .padding(.vertical, KWSpacing.sm)
            .frame(minHeight: KWLayout.minTouch)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
