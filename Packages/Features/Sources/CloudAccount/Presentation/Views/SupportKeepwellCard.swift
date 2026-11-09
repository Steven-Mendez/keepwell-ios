import CloudAccountDomain
import DesignSystem
import SwiftUI

/// "Needs support": what the coffee adds, the price, and restore for a new install. Shown while the
/// plan is free, including during early access, so nobody is surprised when it ends.
struct SupportKeepwellCard: View {
    let viewModel: CloudAccountViewModel
    let user: CloudAccountUser

    var body: some View {
        VStack(alignment: .leading, spacing: KWSpacing.sm) {
            Text("Invite me a coffee", bundle: #bundle).font(KWTextStyle.body.font.weight(.semibold))
            Text(explanation).font(KWTextStyle.caption.font).foregroundStyle(KWColor.Text.secondary)
            Button {
                Task { await viewModel.buyCoffee() }
            } label: {
                if let price = viewModel.coffeePrice {
                    Text("Buy a coffee for \(price)", bundle: #bundle).frame(maxWidth: .infinity)
                } else {
                    Text("Buy a coffee", bundle: #bundle).frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isWorking)
            Button {
                Task { await viewModel.restorePurchases() }
            } label: {
                Text("Restore purchases", bundle: #bundle)
            }
            .font(KWTextStyle.caption.font)
            .disabled(viewModel.isWorking)
            if let message = viewModel.supportMessage {
                Text(message).font(KWTextStyle.caption.font).foregroundStyle(KWColor.Text.secondary)
            }
        }
    }

    private var explanation: String {
        if user.canSync, user.earlyAccess.contains("cloud_sync") {
            return String(
                // swiftlint:disable:next line_length
                localized: "Sync is included during early access. A one-time coffee keeps it, and lets Claude read and record your finances.",
                bundle: #bundle,
            )
        }
        return String(
            localized: "Sync with the web and Claude come with a one-time coffee. Everything else stays free and works on this iPhone.",
            bundle: #bundle,
        )
    }
}
