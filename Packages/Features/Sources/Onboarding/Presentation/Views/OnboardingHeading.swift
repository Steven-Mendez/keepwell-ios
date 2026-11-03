import DesignSystem
import SwiftUI

/// 26pt step title with the muted explanation under it, shared by the onboarding steps.
struct OnboardingHeading: View {
    let title: String
    let message: String

    var body: some View {
        Text(title)
            .kwTextStyle(.titleSm)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, KWSpacing.xxs)
            .accessibilityAddTraits(.isHeader)
        Text(message)
            .font(KWTextStyle.body.font)
            .foregroundStyle(KWColor.Text.muted)
            .lineSpacing(4)
            .fixedSize(horizontal: false, vertical: true)
    }
}
