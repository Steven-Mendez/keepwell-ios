import DesignSystem
import Domain
import SharedPresentation
import SwiftUI

/// A single-choice list in a sheet, styled like the payment-method step of a new movement.
struct RecurringChoiceSheet<Option: Identifiable, Row: View>: View {
    let title: String
    let options: [Option]
    let isSelected: (Option) -> Bool
    @ViewBuilder let row: (Option) -> Row
    let onSelect: (Option) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KWSpacing.sm) {
                Text(title)
                    .kwTextStyle(.titleSm)
                    .accessibilityAddTraits(.isHeader)
                KWGroupedCard {
                    ForEach(options) { option in
                        Button { onSelect(option) } label: {
                            HStack(spacing: KWSpacing.sm) {
                                row(option)
                                if isSelected(option) {
                                    SelectedMark()
                                }
                            }
                            .padding(.vertical, KWSpacing.sm)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(isSelected(option) ? .isSelected : [])
                    }
                }
            }
            .padding(KWLayout.gutter)
            .padding(.top, KWSpacing.xs)
        }
        .scrollIndicators(.hidden)
        .foregroundStyle(KWColor.Text.primary)
    }
}

/// Leading art, a title and a muted subtitle.
struct RecurringChoiceRow<Leading: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder let leading: () -> Leading

    var body: some View {
        leading()
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.kw(15, weight: 600))
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle).font(KWTextStyle.captionSm.font).foregroundStyle(KWColor.Text.muted)
            }
        }
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The card, transfer tile or banknote that stands for a payment method.
struct MethodThumbnail: View {
    let thumbnail: RecurringRuleEditorViewModel.MethodOption.Thumbnail

    var body: some View {
        switch thumbnail {
        case let .card(color): KWMiniCard(.palette(CardDisplay.palette(for: color), chip: false), size: .small)
        case .transfer: KWMiniCard(.transfer, size: .small)
        case .cash: KWMiniCard(.solid(KWColor.State.positive), size: .small)
        }
    }
}

/// The green check on the chosen row.
struct SelectedMark: View {
    var body: some View {
        KWIconView(.check, size: 14, lineWidth: 3)
            .foregroundStyle(KWColor.Text.onPositive)
            .frame(width: 24, height: 24)
            .background(KWColor.State.positive, in: Circle())
            .accessibilityHidden(true)
    }
}

/// A rule's next dates and the movements it recorded, under the editor's fields.
struct RecurringRuleDetail: View {
    let viewModel: RecurringRuleEditorViewModel
    let onOpenTransaction: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: KWSpacing.xs) {
            KWSectionHeader(String(localized: "Next dates", bundle: #bundle))
            KWGroupedCard {
                if viewModel.isPaused {
                    KWValueRow(String(localized: "Paused", bundle: #bundle), value: "", style: .placeholder)
                }
                if viewModel.nextDates.isEmpty, !viewModel.isPaused {
                    KWValueRow(String(localized: "Ended", bundle: #bundle), value: "", style: .placeholder)
                }
                ForEach(Array(viewModel.nextDates.enumerated()), id: \.offset) { _, day in
                    KWValueRow(day, value: viewModel.repeatsTitle, style: .navigation)
                        // Paused: they show where it would fall again, not that it will.
                        .opacity(viewModel.isPaused ? 0.55 : 1)
                }
            }
            if let display = viewModel.display, !viewModel.recorded.isEmpty {
                KWSectionHeader(String(localized: "Recorded", bundle: #bundle))
                    .padding(.top, KWSpacing.xs)
                KWGroupedCard(verticalPadding: KWSpacing.xxs) {
                    ForEach(viewModel.recorded) { transaction in
                        Button { onOpenTransaction(transaction.id) } label: {
                            KWTransactionRow(
                                display.style(of: transaction),
                                title: viewModel.recordedDay(transaction),
                                subtitle: transaction.isConfirmed
                                    ? display.methodName(of: transaction)
                                    : String(localized: "Draft", bundle: #bundle),
                                amount: display.amount(of: transaction),
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}
