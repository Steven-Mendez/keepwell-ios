import DesignSystem
import SwiftUI

/// Step 6 · Privacy and notifications. The lock itself was chosen on the step before.
public struct PrivacyView: View {
    @Bindable private var viewModel: OnboardingViewModel
    private let onBack: () -> Void

    public init(viewModel: OnboardingViewModel, onBack: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onBack = onBack
    }

    public var body: some View {
        KWScreen(bottom: 40) {
            VStack(alignment: .leading, spacing: KWSpacing.md) {
                KWFlowHeader(.back, progress: (5, 5), action: onBack)
                OnboardingHeading(
                    title: String(localized: "Your data stays yours", bundle: #bundle),
                    message: String(
                        localized: "No account and no servers of ours. Your data lives on your iPhone and, if you want, in your iCloud.",
                        bundle: #bundle,
                    ),
                )
                protectionToggles
                notificationsCard
                Spacer(minLength: 0)
                if let message = viewModel.errorMessage {
                    Text(message)
                        .font(KWTextStyle.caption.font)
                        .foregroundStyle(KWColor.State.negative)
                        .frame(maxWidth: .infinity)
                }
                VStack(spacing: KWSpacing.md) {
                    Button { Task { await viewModel.allowNotifications() } } label: { Text("Allow notifications", bundle: #bundle) }
                        .buttonStyle(.kw())
                    Button { Task { await viewModel.skipNotifications() } } label: { Text("Not now", bundle: #bundle) }
                        .buttonStyle(.kw(.plain, size: .text))
                }
                .disabled(viewModel.isSaving)
            }
        }
    }

    private var protectionToggles: some View {
        KWGroupedCard {
            toggle(
                String(localized: "iCloud backup", bundle: #bundle),
                String(localized: "Recover everything if you change iPhone", bundle: #bundle),
                isOn: $viewModel.backsUpToICloud,
            )
            toggle(
                String(localized: "Hide amounts when leaving", bundle: #bundle),
                String(localized: "In the app switcher", bundle: #bundle),
                isOn: $viewModel.hidesAmountsInAppSwitcher,
            )
        }
    }

    private func toggle(_ title: String, _ subtitle: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            KWTitleSubtitle(title, subtitle: subtitle)
        }
        .toggleStyle(.kw)
        .padding(.vertical, 14)
    }

    private var notificationsCard: some View {
        VStack(alignment: .leading, spacing: KWSpacing.sm) {
            Text("Useful notifications, no spam", bundle: #bundle).font(.kw(15, weight: 700))
            VStack(alignment: .leading, spacing: 10) {
                bullet(KWColor.State.pending, String(localized: "Expected expenses due today", bundle: #bundle))
                bullet(KWColor.Brand.accent, String(localized: "Statement and payment dates for your cards", bundle: #bundle))
                bullet(KWColor.State.extra, String(localized: "Limits on additional cards", bundle: #bundle))
            }
            .font(KWTextStyle.label.font.weight(.regular))
            .foregroundStyle(KWColor.Text.secondary)
        }
        .padding(KWSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(KWColor.Surface.surface, in: RoundedRectangle(cornerRadius: KWRadius.surface))
    }

    private func bullet(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 10) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text)
        }
    }
}
