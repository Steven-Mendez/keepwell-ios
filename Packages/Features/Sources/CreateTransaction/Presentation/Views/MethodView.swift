import CreateTransactionDomain
import DesignSystem
import SharedPresentation
import SwiftUI

/// Step 3 · Medio de pago. The method decides which account moves.
public struct MethodView: View {
    private let viewModel: CreateTransactionViewModel
    private let onBack: () -> Void

    public init(viewModel: CreateTransactionViewModel, onBack: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onBack = onBack
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KWSpacing.sm) {
                KWFlowHeader(.back, progress: (4, 3), action: onBack)
                Text(viewModel.methodTitle)
                    .kwTextStyle(.titleSm)
                    .padding(.top, KWSpacing.xxs)
                    .accessibilityAddTraits(.isHeader)
                Text(viewModel.methodMessage)
                    .font(KWTextStyle.label.font.weight(.regular))
                    .foregroundStyle(KWColor.Text.muted)
                    .padding(.bottom, KWSpacing.xxs)
                ForEach(viewModel.methodGroups) { group in
                    Text(group.title)
                        .font(.kw(13, weight: 600, relativeTo: .footnote))
                        .foregroundStyle(KWColor.Text.muted)
                        .padding(.top, KWSpacing.xxs)
                    KWGroupedCard(horizontalPadding: 14) {
                        ForEach(group.rows) { row in
                            Button { viewModel.selectSource(row.source) } label: { content(row) }
                                .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, KWLayout.gutter)
            .padding(.top, KWLayout.safeTop)
            .padding(.bottom, 34)
        }
        .scrollIndicators(.hidden)
        .ignoresSafeArea(edges: .top)
        .background(KWColor.Surface.bg)
        .foregroundStyle(KWColor.Text.primary)
    }

    private func content(_ row: MethodRow) -> some View {
        HStack(spacing: KWSpacing.sm) {
            thumbnail(row.thumbnail)
            VStack(alignment: .leading, spacing: 1) {
                Text(row.title).font(.kw(15, weight: 600))
                if let subtitle = row.subtitle, !subtitle.isEmpty {
                    Text(subtitle).font(KWTextStyle.captionSm.font).foregroundStyle(KWColor.Text.muted)
                }
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            if row.source == viewModel.source {
                SelectedCheck()
            }
        }
        .padding(.vertical, KWSpacing.sm)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func thumbnail(_ thumbnail: MethodRow.Thumbnail) -> some View {
        switch thumbnail {
        case let .card(color): KWMiniCard(.palette(CardDisplay.palette(for: color)))
        case .transfer: KWMiniCard(.neutral)
        case .cash: KWMiniCard(.solid(KWColor.State.positive))
        }
    }
}
