import DesignSystem
import SwiftUI

/// Step 1 · Welcome, and the one decision before setup: an existing Keepwell account or none.
/// With the Keepwell API, `accountChoice` (the account feature's sign-in) takes the place of
/// "Start": signing in comes first, right on the welcome (Mobbin: Monarch, Wise, Fuse), and using
/// Keepwell without an account sits under it as a real choice (Buddy's "Continue Anonymous").
public struct WelcomeView: View {
    private let accountChoice: AnyView?
    private let onStart: () -> Void

    public init(accountChoice: AnyView? = nil, onStart: @escaping () -> Void) {
        self.accountChoice = accountChoice
        self.onStart = onStart
    }

    public var body: some View {
        if let accountChoice {
            // The sign-in options and the invitation field don't fit every iPhone under the pitch:
            // it scrolls when it has to, and the field can scroll above the keyboard.
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    CardsIllustration(height: 200)
                    pitch
                    accountChoice
                        .padding(.top, KWSpacing.xl)
                }
                .padding(.top, KWLayout.safeTop)
                .padding(.bottom, KWSpacing.lg)
                .padding(.horizontal, KWLayout.gutter)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
            .foregroundStyle(KWColor.Text.primary)
            .background { KWGlowBackground(.brand).ignoresSafeArea() }
        } else {
            KWScreen(top: 64, bottom: 40) {
                KWGlowBackground(.brand)
            } content: {
                VStack(alignment: .leading, spacing: 0) {
                    CardsIllustration(height: 260)
                    pitch
                    VStack(alignment: .leading, spacing: 14) {
                        feature(.phone, String(localized: "Stays on your iPhone", bundle: #bundle))
                        feature(.transfer, String(localized: "Any currency, with your own rate", bundle: #bundle))
                    }
                    .padding(.top, KWSpacing.xl)
                    Spacer(minLength: KWSpacing.md)
                    Button(action: onStart) { Text("Start", bundle: #bundle) }
                        .buttonStyle(.kw())
                }
            }
        }
    }

    private var pitch: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("All your money, in one place", bundle: #bundle)
                .font(.kw(30, weight: 800, relativeTo: .title))
                .tracking(-1)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text("Keep clear accounts in one or more currencies. Log expenses, transfers and drafts at your own pace.", bundle: #bundle)
                .font(.kw(17, weight: 400))
                .foregroundStyle(KWColor.Text.onBrand)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 28)
    }

    private func feature(_ icon: KWIcon, _ text: String) -> some View {
        HStack(spacing: KWSpacing.sm) {
            KWIconView(icon, size: 18)
                .frame(width: 36, height: 36)
                .background(KWColor.Text.primary.opacity(0.12), in: Circle())
            Text(text).font(KWTextStyle.body.font)
        }
    }
}

/// Three fanned cards from the welcome artwork.
private struct CardsIllustration: View {
    let height: CGFloat

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
        // Drawn at the artwork's 260 points and scaled, so a shorter welcome keeps every card whole.
        .scaleEffect(height / 260, anchor: .topLeading)
        .frame(height: height, alignment: .topLeading)
        // Card art: the same lime, graphite and blue cards in both appearances.
        .kwBrandSurface()
        .accessibilityHidden(true)
    }
}

#Preview {
    WelcomeView(onStart: {})
        .onAppear { KWFonts.register() }
}
