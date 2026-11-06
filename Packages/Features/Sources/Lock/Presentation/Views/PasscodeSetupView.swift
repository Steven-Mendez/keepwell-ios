import DesignSystem
import SwiftUI

/// Create or change the app passcode: type six digits, then again to confirm.
public struct PasscodeSetupView: View {
    @Bindable private var viewModel: PasscodeSetupViewModel
    private let isChanging: Bool
    private let onClose: () -> Void

    public init(viewModel: PasscodeSetupViewModel, isChanging: Bool, onClose: @escaping () -> Void) {
        self.viewModel = viewModel
        self.isChanging = isChanging
        self.onClose = onClose
    }

    public var body: some View {
        KWScreen(top: KWSpacing.xl, bottom: 40, horizontal: KWSpacing.xl) {
            KWColor.Surface.bg
        } content: {
            VStack(spacing: 0) {
                HStack {
                    KWCircleButton(.close, accessibilityLabel: String(localized: "Close", bundle: #bundle), action: onClose)
                    Spacer()
                }
                heading
                KWPasscodeDots(length: LockStrings.passcodeLength, filled: viewModel.entered.count, isError: viewModel.isError)
                    .kwShake(viewModel.rejections)
                    .padding(.top, KWSpacing.xxl)
                messageLine
                Spacer(minLength: KWSpacing.md)
                KWKeypad(
                    isEnabled: !viewModel.isSaving,
                    onDigit: { digit in Task { await viewModel.press(digit) } },
                    onDelete: viewModel.deleteDigit,
                )
            }
            .frame(maxWidth: .infinity)
        }
        .task(id: viewModel.rejections) {
            guard viewModel.isError else { return }
            try? await Task.sleep(for: .milliseconds(700))
            if viewModel.isError {
                viewModel.clearError()
            }
        }
        .sensoryFeedback(.error, trigger: viewModel.rejections)
        .sensoryFeedback(.selection, trigger: viewModel.step)
        .sensoryFeedback(.success, trigger: viewModel.isSaved) { _, saved in saved }
        .onChange(of: viewModel.isSaved) { _, saved in
            if saved {
                onClose()
            }
        }
    }

    @ViewBuilder
    private var heading: some View {
        Text(title)
            .font(.kw(26, weight: 800, relativeTo: .title2))
            .tracking(-0.6)
            .multilineTextAlignment(.center)
            .padding(.top, KWSpacing.xxl)
            .accessibilityAddTraits(.isHeader)
        Text(subtitle)
            .font(KWTextStyle.body.font)
            .foregroundStyle(KWColor.Text.secondary)
            .multilineTextAlignment(.center)
            .padding(.top, KWSpacing.xs)
    }

    /// Keeps its height when empty, so the keypad doesn't jump when an error comes and goes.
    private var messageLine: some View {
        Group {
            if let message = viewModel.message {
                Text(message)
                    .font(KWTextStyle.label.font)
                    .foregroundStyle(KWColor.State.negative)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(minHeight: 40)
        .padding(.top, KWSpacing.md)
    }

    private var title: String {
        switch (viewModel.step, isChanging) {
        case (.create, false): String(localized: "Create a passcode", bundle: #bundle)
        case (.create, true): String(localized: "Choose a new passcode", bundle: #bundle)
        case (.confirm, _): String(localized: "Confirm your passcode", bundle: #bundle)
        }
    }

    private var subtitle: String {
        switch viewModel.step {
        case .create: String(localized: "Six digits to open Keepwell when Face ID can't. It's kept only on this iPhone.", bundle: #bundle)
        case .confirm: String(localized: "Type it once more.", bundle: #bundle)
        }
    }
}
