import CreateTransactionDomain
import DesignSystem
import Domain
import SharedPresentation
import SwiftUI

/// The receipt: a ticket with what was saved, where it moved, the rate and the new balance, and a
/// text version to share.
public struct SavedView: View {
    private let viewModel: CreateTransactionViewModel
    private let onClose: () -> Void

    public init(viewModel: CreateTransactionViewModel, onClose: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onClose = onClose
    }

    public var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                if let saved = viewModel.saved {
                    ticket(saved)
                        .padding(.top, 36)
                }
            }
            .scrollIndicators(.hidden)
            .contentMargins(.horizontal, KWLayout.gutter, for: .scrollContent)
            .contentMargins(.top, KWLayout.safeTop, for: .scrollContent)
            HStack(spacing: 10) {
                Button { Task { await viewModel.startOver() } } label: { Text("Log another", bundle: #bundle) }
                    .buttonStyle(.kw(.surface, size: .regular))
                Button(action: onClose) { Text("Done", bundle: #bundle) }
                    .buttonStyle(.kw(.primary, size: .regular))
            }
            .padding(.horizontal, KWLayout.gutter)
            .padding(.top, KWSpacing.sm)
            .padding(.bottom, 34)
        }
        .ignoresSafeArea(.container, edges: [.top, .bottom])
        .background(KWColor.Surface.bg)
        .foregroundStyle(KWColor.Text.primary)
    }

    private func ticket(_ saved: SavedTransaction) -> some View {
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
                status(saved)
            }
            KWDivider().padding(.vertical, KWSpacing.xxs)
            VStack(spacing: 0) {
                ForEach(rows(saved), id: \.label) { row in
                    KWValueRow(row.label, value: row.value)
                }
            }
            KWDivider()
            ShareLink(item: viewModel.receiptText(saved)) {
                HStack(spacing: KWSpacing.xs) {
                    KWIconView(.share, size: 18, lineWidth: 2)
                    Text("Share receipt", bundle: #bundle).font(.kw(15, weight: 600))
                }
                .foregroundStyle(KWColor.Brand.link)
                .frame(maxWidth: .infinity)
                .frame(height: KWLayout.minTouch)
            }
            .padding(.bottom, KWSpacing.md)
        }
        .padding(.horizontal, KWSpacing.md)
        .padding(.bottom, 8)
        .background(KWColor.Surface.surface, in: KWTicketShape())
        .overlay(alignment: .top) { checkBadge.offset(y: -30) }
    }

    private func status(_ saved: SavedTransaction) -> some View {
        Text(saved.transaction.isConfirmed ? String(localized: "Confirmed", bundle: #bundle) : String(
            localized: "Planned",
            bundle: #bundle,
        ))
        .font(.kw(12, weight: 700, relativeTo: .caption))
        .foregroundStyle(saved.transaction.isConfirmed ? KWColor.State.positive : KWColor.State.pending)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            (saved.transaction.isConfirmed ? KWColor.State.positive : KWColor.State.pending).opacity(0.14),
            in: Capsule(),
        )
        .padding(.top, KWSpacing.xxs)
    }

    /// Method or ends of the transfer, then the category, note, money rows and the reference.
    private func rows(_ saved: SavedTransaction) -> [CreateTransactionViewModel.Row] {
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
            .overlay(Circle().strokeBorder(KWColor.Surface.bg, lineWidth: 5))
            .accessibilityLabel(Text("Saved", bundle: #bundle))
    }
}
