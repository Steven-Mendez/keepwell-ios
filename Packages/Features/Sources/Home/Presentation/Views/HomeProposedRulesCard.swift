import DesignSystem
import Domain
import SwiftUI

/// Recurring rules an assistant set up wait paused until the person confirms them here; discarding
/// deletes them.
struct HomeProposedRulesCard: View {
    let viewModel: HomeViewModel
    let rules: [RecurringRule]
    let hidesBalances: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: KWSpacing.sm) {
            Text("Proposed by Claude", bundle: #bundle)
                .font(KWTextStyle.heading.font)
                .accessibilityAddTraits(.isHeader)
            ForEach(rules) { rule in
                HStack(spacing: KWSpacing.xs) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(rule.name).font(.kw(15, weight: 600)).lineLimit(1)
                        Text(viewModel.proposalSubtitle(rule, hidden: hidesBalances))
                            .font(KWTextStyle.captionSm.font)
                            .foregroundStyle(KWColor.Text.muted)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if viewModel.canResolveProposals {
                        Button {
                            Task { await viewModel.discardProposal(rule) }
                        } label: {
                            Text("Discard", bundle: #bundle)
                        }
                        .buttonStyle(.kw(.secondary, size: .mini))
                        Button {
                            Task { await viewModel.confirmProposal(rule) }
                        } label: {
                            Text("Confirm", bundle: #bundle)
                        }
                        .buttonStyle(.kw(.primary, size: .mini))
                    }
                }
            }
            if let error = viewModel.actionError {
                Text(error).font(KWTextStyle.caption.font).foregroundStyle(KWColor.State.negative)
            }
        }
        .padding(KWSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(KWColor.Surface.surface, in: RoundedRectangle(cornerRadius: KWRadius.surface, style: .continuous))
    }
}
