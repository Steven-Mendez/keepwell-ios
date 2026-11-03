import DesignSystem
import LockDomain
import SwiftUI

/// Covers the app until the device owner authenticates. It asks once on its own when it
/// appears, then waits for a tap so a cancelled prompt doesn't loop.
public struct LockView: View {
    private let authenticator: any DeviceAuthenticator
    /// Whether the person chose the passcode over biometrics in settings.
    private let prefersPasscode: Bool
    private let showsHiddenAmountsNote: Bool
    private let onUnlock: () -> Void
    @State private var biometry = Biometry.unavailable
    @State private var isAuthenticating = false
    @State private var didAutoPrompt = false

    public init(
        authenticator: any DeviceAuthenticator,
        prefersPasscode: Bool,
        showsHiddenAmountsNote: Bool,
        onUnlock: @escaping () -> Void,
    ) {
        self.authenticator = authenticator
        self.prefersPasscode = prefersPasscode
        self.showsHiddenAmountsNote = showsHiddenAmountsNote
        self.onUnlock = onUnlock
    }

    public var body: some View {
        KWScreen(top: 120, bottom: 48, horizontal: KWSpacing.xl) {
            KWGlowBackground(.brand)
        } content: {
            VStack(spacing: 0) {
                KWAppIconTile()
                Text(verbatim: "keepwell")
                    .font(.kw(26, weight: 800, relativeTo: .title2))
                    .tracking(-0.8)
                    .padding(.top, KWSpacing.xl)
                    .padding(.bottom, KWSpacing.xs)
                Text("Your finances are encrypted on this iPhone", bundle: #bundle)
                    .font(KWTextStyle.body.font)
                    .foregroundStyle(KWColor.Text.onBrand)
                    .multilineTextAlignment(.center)
                if usesBiometrics {
                    biometricButton
                }
                Spacer(minLength: KWSpacing.xl)
                if showsHiddenAmountsNote {
                    hiddenAmountsNote
                }
                Button { authenticate(allowsBiometrics: false) } label: {
                    Text("Use iPhone passcode", bundle: #bundle)
                }
                .buttonStyle(.kw(.primary, size: .regular))
            }
            .frame(maxWidth: .infinity)
            .disabled(isAuthenticating)
        }
        .onAppear {
            biometry = authenticator.biometry()
            guard !didAutoPrompt else { return }
            didAutoPrompt = true
            authenticate(allowsBiometrics: usesBiometrics)
        }
    }

    private var biometricButton: some View {
        VStack(spacing: 0) {
            Button { authenticate(allowsBiometrics: true) } label: {
                KWIconView(biometry == .touchID ? .touchID : .faceID, size: biometry == .touchID ? 56 : 52, lineWidth: 1.6)
                    .foregroundStyle(biometry == .touchID ? KWColor.State.negative : KWColor.Text.primary)
                    .frame(width: 104, height: 104)
                    .background(KWColor.Overlay.white10, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(biometricTitle)
            .padding(.top, 96)
            Text(biometricCaption)
                .font(.kw(15, weight: 600))
                .padding(.top, KWSpacing.md)
        }
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

    private var usesBiometrics: Bool {
        !prefersPasscode && biometry != .unavailable
    }

    private var biometricTitle: String {
        switch biometry {
        case .touchID: String(localized: "Unlock with Touch ID", bundle: #bundle)
        case .opticID: String(localized: "Unlock with Optic ID", bundle: #bundle)
        case .faceID, .unavailable: String(localized: "Unlock with Face ID", bundle: #bundle)
        }
    }

    private var biometricCaption: String {
        switch biometry {
        case .touchID: String(localized: "Rest your finger on the Home button", bundle: #bundle)
        case .opticID: String(localized: "Tap to use Optic ID", bundle: #bundle)
        case .faceID, .unavailable: String(localized: "Tap to use Face ID", bundle: #bundle)
        }
    }

    private func authenticate(allowsBiometrics: Bool) {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        let reason = String(localized: "Unlock Keepwell to see your finances.", bundle: #bundle)
        Task {
            let success = await authenticator.authenticate(reason: reason, allowsBiometrics: allowsBiometrics)
            isAuthenticating = false
            if success {
                onUnlock()
            }
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
