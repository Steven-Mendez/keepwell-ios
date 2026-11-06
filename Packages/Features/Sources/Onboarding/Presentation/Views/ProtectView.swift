import DesignSystem
import SwiftUI

/// Step 5 · Lock the app: the Keepwell passcode and Face ID or Touch ID on top. Offered, never
/// forced; "Not now" still leaves Face ID with the iPhone passcode behind it.
public struct ProtectView: View {
    @Bindable private var viewModel: OnboardingViewModel
    private let onBack: () -> Void
    private let onSetUpPasscode: () -> Void

    public init(viewModel: OnboardingViewModel, onBack: @escaping () -> Void, onSetUpPasscode: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onBack = onBack
        self.onSetUpPasscode = onSetUpPasscode
    }

    public var body: some View {
        KWScreen(bottom: 40) {
            VStack(alignment: .leading, spacing: KWSpacing.md) {
                KWFlowHeader(.back, progress: (5, 4), action: onBack)
                OnboardingHeading(
                    title: String(localized: "Protect Keepwell", bundle: #bundle),
                    message: String(
                        localized: "Your balances are yours alone. Lock the app so only you can open it.",
                        bundle: #bundle,
                    ),
                )
                KWGroupedCard {
                    passcodeRow
                    Toggle(isOn: $viewModel.locksWithBiometrics) {
                        KWTitleSubtitle(
                            String(localized: "Face ID or Touch ID", bundle: #bundle),
                            subtitle: String(localized: "Whichever your iPhone has", bundle: #bundle),
                        )
                    }
                    .toggleStyle(.kw)
                    .padding(.vertical, 14)
                }
                Spacer(minLength: 0)
                VStack(spacing: KWSpacing.md) {
                    if viewModel.hasPasscode {
                        Button(action: viewModel.continueFromProtect) { Text("Continue", bundle: #bundle) }
                            .buttonStyle(.kw())
                    } else {
                        Button(action: onSetUpPasscode) { Text("Create passcode", bundle: #bundle) }
                            .buttonStyle(.kw())
                        Button(action: viewModel.skipPasscode) { Text("Not now", bundle: #bundle) }
                            .buttonStyle(.kw(.plain, size: .text))
                    }
                }
            }
        }
        .sensoryFeedback(.success, trigger: viewModel.hasPasscode) { _, created in created }
    }

    /// Before: what the passcode is. After: that it's on, with a way to choose another.
    private var passcodeRow: some View {
        Button(action: onSetUpPasscode) {
            HStack(spacing: KWSpacing.sm) {
                KWTitleSubtitle(
                    String(localized: "Keepwell passcode", bundle: #bundle),
                    subtitle: viewModel.hasPasscode
                        ? String(localized: "On · tap to choose another", bundle: #bundle)
                        : String(localized: "Six digits, kept only on this iPhone", bundle: #bundle),
                )
                Spacer(minLength: KWSpacing.xs)
                if viewModel.hasPasscode {
                    KWIconView(.check, size: 14, lineWidth: 2.6)
                        .foregroundStyle(KWColor.Text.onPositive)
                        .frame(width: 26, height: 26)
                        .background(KWColor.State.positive, in: Circle())
                        .accessibilityHidden(true)
                } else {
                    KWIconView(.chevronRight, size: 16)
                        .foregroundStyle(KWColor.Text.muted)
                        .accessibilityHidden(true)
                }
            }
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(viewModel.hasPasscode ? Text("On", bundle: #bundle) : Text(verbatim: ""))
    }
}
