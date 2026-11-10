import DesignSystem
import LockDomain
import SwiftUI

/// Covers the app until the owner unlocks it. With an app passcode it's a greeting over a keypad
/// whose corner key is Face ID or Touch ID, prompted once on its own; without one it offers the
/// iPhone's own sheet. Either way it asks once when it appears, then waits for a tap, so a
/// cancelled prompt doesn't loop.
public struct LockView: View {
    @Bindable private var viewModel: LockViewModel
    private let showsHiddenAmountsNote: Bool
    private let onUnlock: () -> Void
    @Environment(\.scenePhase) private var scenePhase
    @State private var wasInBackground = false

    public init(viewModel: LockViewModel, showsHiddenAmountsNote: Bool, onUnlock: @escaping () -> Void) {
        self.viewModel = viewModel
        self.showsHiddenAmountsNote = showsHiddenAmountsNote
        self.onUnlock = onUnlock
    }

    public var body: some View {
        KWScreen(top: 96, bottom: 32, horizontal: KWSpacing.xl) {
            KWGlowBackground(.brand)
        } content: {
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                VStack(spacing: 0) {
                    header(at: timeline.date)
                    switch viewModel.mode {
                    case .loading: Spacer()
                    case .keypad: keypad(at: timeline.date)
                    case .system: system
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .task { await viewModel.appear() }
        .task(id: viewModel.rejections) {
            guard viewModel.isError else { return }
            try? await Task.sleep(for: .milliseconds(700))
            if viewModel.isError {
                viewModel.clearError()
            }
        }
        .sensoryFeedback(.error, trigger: viewModel.rejections)
        .sensoryFeedback(.success, trigger: viewModel.isUnlocked) { _, unlocked in unlocked }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                wasInBackground = true
            } else if phase == .active, wasInBackground {
                wasInBackground = false
                Task { await viewModel.returnedFromBackground() }
            }
        }
        .onChange(of: viewModel.isUnlocked) { _, unlocked in
            if unlocked {
                onUnlock()
            }
        }
    }

    // MARK: - Header

    private func header(at date: Date) -> some View {
        VStack(spacing: 0) {
            avatar
            Text(viewModel.greeting(at: date))
                .font(.kw(26, weight: 800, relativeTo: .title2))
                .tracking(-0.6)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .padding(.top, KWSpacing.lg)
                .accessibilityAddTraits(.isHeader)
            Text(subtitle)
                .font(KWTextStyle.body.font)
                .foregroundStyle(KWColor.Text.onBrand)
                .multilineTextAlignment(.center)
                .padding(.top, KWSpacing.xs)
        }
    }

    /// The person's initial when the app knows their name, otherwise the app's own mark.
    @ViewBuilder
    private var avatar: some View {
        if let initial = viewModel.preferredName?.first {
            Text(String(initial).uppercased())
                .font(.kw(28, weight: 800, relativeTo: .title2))
                .frame(width: 72, height: 72)
                .background(KWColor.Text.primary.opacity(0.14), in: Circle())
                .accessibilityHidden(true)
        } else {
            KWAppIconTile().scaleEffect(0.75).frame(width: 72, height: 72)
        }
    }

    private var subtitle: String {
        switch viewModel.mode {
        case .keypad: String(localized: "Enter your Keepwell passcode", bundle: #bundle)
        case .loading, .system: String(localized: "Your finances are encrypted on this iPhone", bundle: #bundle)
        }
    }

    // MARK: - Keypad

    private func keypad(at date: Date) -> some View {
        let isLockedOut = viewModel.isLockedOut(at: date)
        return VStack(spacing: 0) {
            KWPasscodeDots(length: LockStrings.passcodeLength, filled: viewModel.entered.count, isError: viewModel.isError)
                .kwShake(viewModel.rejections)
                .padding(.top, KWSpacing.xxl)
            status(isLockedOut: isLockedOut, at: date)
                .frame(minHeight: 40)
                .padding(.top, KWSpacing.md)
            Spacer(minLength: KWSpacing.md)
            // Face ID stays available during a passcode lockout: it's the stronger proof.
            KWKeypad(
                isEnabled: !isLockedOut && !viewModel.isAuthenticating,
                onDigit: { digit in Task { await viewModel.press(digit) } },
                onDelete: viewModel.deleteDigit,
                accessory: { biometricKey },
            )
            Button { Task { await viewModel.forgotPasscode() } } label: {
                Text("Forgot your passcode?", bundle: #bundle)
                    .font(.kw(15, weight: 600))
                    .foregroundStyle(KWColor.Brand.link)
                    .frame(minHeight: KWLayout.minTouch)
            }
            .buttonStyle(.plain)
            .padding(.top, KWSpacing.md)
        }
    }

    @ViewBuilder
    private var biometricKey: some View {
        if viewModel.offersBiometrics {
            Button { Task { await viewModel.useBiometrics() } } label: {
                KWIconView(biometricIcon, size: 34, lineWidth: 1.6)
                    .frame(width: 76, height: 76)
                    .contentShape(Circle())
            }
            .buttonStyle(KWKeyStyle(filled: false))
            .accessibilityLabel(biometricTitle)
        }
    }

    @ViewBuilder
    private func status(isLockedOut: Bool, at date: Date) -> some View {
        if isLockedOut, let until = viewModel.lockedUntil {
            Text("Too many tries. Try again in \(LockStrings.remaining(until: until, now: date)).", bundle: #bundle)
                .font(KWTextStyle.label.font)
                .foregroundStyle(KWColor.State.negative)
                .multilineTextAlignment(.center)
                .monospacedDigit()
        } else if let message = viewModel.message {
            Text(message)
                .font(KWTextStyle.label.font)
                .foregroundStyle(KWColor.State.negative)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - System

    private var system: some View {
        VStack(spacing: 0) {
            if viewModel.offersBiometrics {
                Button { Task { await viewModel.useDevice(allowsBiometrics: true) } } label: {
                    KWIconView(biometricIcon, size: viewModel.biometry == .touchID ? 56 : 52, lineWidth: 1.6)
                        .foregroundStyle(viewModel.biometry == .touchID ? KWColor.State.negative : KWColor.Text.primary)
                        .frame(width: 104, height: 104)
                        .background(KWColor.Text.primary.opacity(0.10), in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(biometricTitle)
                .padding(.top, 96)
                Text(biometricCaption)
                    .font(.kw(15, weight: 600))
                    .padding(.top, KWSpacing.md)
            }
            Spacer(minLength: KWSpacing.xl)
            if showsHiddenAmountsNote {
                hiddenAmountsNote
            }
            Button { Task { await viewModel.useDevice(allowsBiometrics: false) } } label: {
                Text("Use iPhone passcode", bundle: #bundle)
            }
            .buttonStyle(.kw(.primary, size: .regular))
        }
        .disabled(viewModel.isAuthenticating)
    }

    private var hiddenAmountsNote: some View {
        HStack(spacing: KWSpacing.sm) {
            KWIconView(.eyeOff, size: 22).foregroundStyle(KWColor.Brand.link)
            Text("Amounts hidden in the app switcher and screenshots", bundle: #bundle)
                .font(KWTextStyle.label.font.weight(.regular))
                .foregroundStyle(KWColor.Text.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, KWSpacing.md)
        .padding(.vertical, 14)
        .background(KWColor.Surface.surface, in: RoundedRectangle(cornerRadius: KWRadius.surface, style: .continuous))
        .padding(.bottom, KWSpacing.md)
    }

    // MARK: - Wording

    private var biometricIcon: KWIcon {
        viewModel.biometry == .touchID ? .touchID : .faceID
    }

    private var biometricTitle: String {
        switch viewModel.biometry {
        case .touchID: String(localized: "Unlock with Touch ID", bundle: #bundle)
        case .opticID: String(localized: "Unlock with Optic ID", bundle: #bundle)
        case .faceID, .unavailable: String(localized: "Unlock with Face ID", bundle: #bundle)
        }
    }

    private var biometricCaption: String {
        switch viewModel.biometry {
        case .touchID: String(localized: "Rest your finger on the Home button", bundle: #bundle)
        case .opticID: String(localized: "Tap to use Optic ID", bundle: #bundle)
        case .faceID, .unavailable: String(localized: "Tap to use Face ID", bundle: #bundle)
        }
    }
}

/// Shown over the app in the app switcher when amounts are hidden, so balances never appear in
/// the snapshot iOS takes.
public struct PrivacyCoverView: View {
    public init() {}

    public var body: some View {
        ZStack {
            KWGlowBackground(.brand)
            KWAppIconTile()
        }
        .accessibilityHidden(true)
    }
}
