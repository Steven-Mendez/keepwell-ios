import DesignSystem
import SwiftUI

/// Step 1 · Welcome.
public struct WelcomeView: View {
    private let restoreState: OnboardingViewModel.RestoreState
    private let onStart: () -> Void
    private let onRestore: () -> Void

    public init(restoreState: OnboardingViewModel.RestoreState, onStart: @escaping () -> Void, onRestore: @escaping () -> Void) {
        self.restoreState = restoreState
        self.onStart = onStart
        self.onRestore = onRestore
    }

    public var body: some View {
        KWScreen(top: 64, bottom: 40, horizontal: 20) {
            KWGlowBackground(.brand)
        } content: {
            VStack(alignment: .leading, spacing: 0) {
                CardsIllustration()
                Text("Your money, clear, in one or two currencies", bundle: #bundle)
                    .font(.kw(30, weight: 800, relativeTo: .title))
                    .tracking(-1)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 28)
                    .padding(.bottom, 12)
                    .accessibilityAddTraits(.isHeader)
                Text("Log expenses, income and transfers. Cards with extras, cash and expected expenses.", bundle: #bundle)
                    .font(.kw(17, weight: 400))
                    .foregroundStyle(KWColor.Text.onBrand)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 14) {
                    feature(.personOff, String(localized: "No account or sign-up", bundle: #bundle))
                    feature(.phone, String(localized: "On your iPhone, backed up to your iCloud", bundle: #bundle))
                    feature(.transfer, String(localized: "Any currency, with your own rate", bundle: #bundle))
                }
                .padding(.top, KWSpacing.xl)
                Spacer(minLength: KWSpacing.md)
                Button(action: onStart) { Text("Start", bundle: #bundle) }
                    .buttonStyle(.kw())
                restoreButton
                if restoreState == .notFound {
                    Text("We couldn't find a backup in your iCloud.", bundle: #bundle)
                        .font(KWTextStyle.caption.font)
                        .foregroundStyle(KWColor.Text.muted)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var restoreButton: some View {
        Button(action: onRestore) {
            HStack(spacing: KWSpacing.xs) {
                KWIconView(.cloud, size: 18)
                if restoreState == .searching {
                    Text("Looking for your backup…", bundle: #bundle)
                } else {
                    Text("I've used it before: restore from iCloud", bundle: #bundle)
                }
            }
        }
        .buttonStyle(KWButtonStyle(.plain, size: .text, height: 48))
        .disabled(restoreState == .searching)
        .padding(.top, 10)
    }

    private func feature(_ icon: KWIcon, _ text: String) -> some View {
        HStack(spacing: KWSpacing.sm) {
            KWIconView(icon, size: 18)
                .frame(width: 36, height: 36)
                .background(KWColor.Overlay.white12, in: Circle())
            Text(text).font(KWTextStyle.body.font)
        }
    }
}

/// Three fanned cards from the welcome artwork.
private struct CardsIllustration: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 16)
                .fill(KWColor.State.extra)
                .frame(width: 230, height: 145)
                .rotationEffect(.degrees(-12))
                .offset(x: 50, y: 30)
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(hex: 0x1E1E24))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(KWColor.Surface.border, lineWidth: 1))
                .frame(width: 230, height: 145)
                .rotationEffect(.degrees(-4))
                .offset(x: 70, y: 60)
            VStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(KWColor.CardArt.chip.gradient)
                    .frame(width: 34, height: 25)
                Spacer()
                Text(verbatim: "$11,157.46")
                    .font(.kw(20, weight: 800))
                    .tracking(-0.5)
            }
            .padding(KWSpacing.md)
            .frame(width: 230, height: 145, alignment: .leading)
            .background(KWColor.Brand.b500, in: RoundedRectangle(cornerRadius: 16))
            .shadow(color: Color(hex: 0x2F5BFF, opacity: 0.4), radius: 20, y: 20)
            .rotationEffect(.degrees(5))
            .offset(x: 90, y: 92)
        }
        .frame(maxWidth: .infinity, minHeight: 260, maxHeight: 260, alignment: .topLeading)
        .accessibilityHidden(true)
    }
}

#Preview {
    WelcomeView(restoreState: .idle, onStart: {}, onRestore: {})
        .onAppear { KWFonts.register() }
}
