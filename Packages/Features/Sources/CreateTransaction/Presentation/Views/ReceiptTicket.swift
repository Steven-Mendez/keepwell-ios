import CreateTransactionDomain
import DesignSystem
import Domain
import SharedPresentation
import SwiftUI

/// The ticket itself, shared by the receipt screen and the image it saves or shares, so both
/// always say the same thing. `footer` holds the screen's actions; the image has none.
struct ReceiptTicket<Footer: View>: View {
    let viewModel: CreateTransactionViewModel
    let saved: SavedTransaction
    /// What shows around the ticket, so the badge reads as punched through it.
    var backdrop: Color = KWColor.Surface.bg
    @ViewBuilder let footer: Footer

    var body: some View {
        VStack(spacing: KWSpacing.sm) {
            Text(viewModel.receiptDate(saved))
                .font(KWTextStyle.captionSm.font)
                .foregroundStyle(KWColor.Text.muted)
                .multilineTextAlignment(.center)
                .padding(.top, 40)
            VStack(spacing: 2) {
                Text(viewModel.receiptHeadline).font(KWTextStyle.label.font).foregroundStyle(KWColor.Text.secondary)
                Text(viewModel.reviewAmount)
                    .font(.kw(40, weight: 800, relativeTo: .largeTitle))
                    .tracking(-1)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(saved.transaction.description).font(.kw(17, weight: 600))
                status
            }
            KWDivider().padding(.vertical, KWSpacing.xxs)
            VStack(spacing: 0) {
                ForEach(rows, id: \.label) { row in
                    KWValueRow(row.label, value: row.value)
                }
            }
            footer
        }
        .padding(.horizontal, KWSpacing.md)
        .padding(.bottom, 8)
        .background(KWColor.Surface.surface, in: KWTicketShape())
        .overlay(alignment: .top) { checkBadge.offset(y: -30) }
    }

    private var status: some View {
        let confirmed = saved.transaction.isConfirmed
        let color = confirmed ? KWColor.State.positive : KWColor.State.pending
        return Text(confirmed ? String(localized: "Confirmed", bundle: #bundle) : String(localized: "Planned", bundle: #bundle))
            .font(.kw(12, weight: 700, relativeTo: .caption))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color.opacity(0.14), in: Capsule())
            .padding(.top, KWSpacing.xxs)
    }

    /// Method or ends of the transfer, then the category, note, money rows and the reference.
    private var rows: [CreateTransactionViewModel.Row] {
        var rows: [CreateTransactionViewModel.Row] = []
        if viewModel.type.movesBetweenAccounts {
            if let from = viewModel.fromParty {
                rows.append(.init(label: from.caption, value: from.title))
            }
            if let toParty = viewModel.toParty {
                rows.append(.init(label: toParty.caption, value: toParty.title))
            }
        } else {
            rows.append(.init(label: String(localized: "Method", bundle: #bundle), value: viewModel.sourceTitle ?? "—"))
            if let category = viewModel.category {
                rows.append(.init(label: String(localized: "Category", bundle: #bundle), value: CategoryDisplay.name(of: category)))
            }
        }
        if let note = saved.transaction.note {
            rows.append(.init(label: String(localized: "Note", bundle: #bundle), value: note))
        }
        rows += viewModel.savedRows(saved)
        if let arrived = viewModel.arrivedRow {
            rows.append(arrived)
        }
        if let total = viewModel.categoryTotalRow(saved) {
            rows.append(total)
        }
        rows.append(.init(label: String(localized: "Reference", bundle: #bundle), value: viewModel.reference(saved)))
        return rows
    }

    private var checkBadge: some View {
        KWIconView(.check, size: 28, lineWidth: 2.8)
            .foregroundStyle(KWColor.Text.onPositive)
            .frame(width: 60, height: 60)
            .background(KWColor.State.positive, in: Circle())
            .overlay(Circle().strokeBorder(backdrop, lineWidth: 5))
            .accessibilityLabel(Text("Saved", bundle: #bundle))
    }
}
