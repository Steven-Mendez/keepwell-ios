import Core
import DesignSystem
import Domain
import SwiftUI
import TransactionsDomain

/// "Filters" at the end of the kind chips: opens the sheet with the amount range and the origin.
struct FiltersChip: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text("Filters", bundle: #bundle)
                    .font(KWTextStyle.label.font)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .bold))
            }
            .padding(.horizontal, KWSpacing.md)
            .frame(height: KWComponentMetrics.chipHeight)
            .foregroundStyle(KWColor.Text.secondary)
            .background(KWColor.Surface.surface, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// An active amount or origin filter, styled like the account chip while it narrows the list
/// (Origin): filled, a tap reopens the sheet, its ✕ clears it. The title says what it filters, so
/// the state never rests on color alone.
struct ActiveFilterChipView: View {
    let chip: ActiveFilterChip
    let onOpen: () -> Void
    let onClear: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onOpen) {
                Text(chip.title)
                    .font(KWTextStyle.label.font)
                    .lineLimit(1)
                    .padding(.leading, KWSpacing.md)
                    .padding(.trailing, KWSpacing.xxs)
                    .frame(height: KWComponentMetrics.chipHeight)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text("Filters", bundle: #bundle))
            Button(action: onClear) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 32, height: KWComponentMetrics.chipHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Remove filter \(chip.title)", bundle: #bundle))
        }
        .foregroundStyle(KWColor.Semantic.primaryForeground)
        .background(KWColor.Semantic.primary, in: Capsule())
    }
}

/// bunq's two rows: the amount in the principal currency (minimum and maximum) and the origin (all
/// movements or subscriptions only). "Apply" stays off while the minimum is above the maximum.
struct FiltersSheet: View {
    let viewModel: TransactionsViewModel
    let onClose: () -> Void
    @State private var draft: MoreFiltersDraft

    init(viewModel: TransactionsViewModel, onClose: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onClose = onClose
        _draft = State(initialValue: viewModel.makeFiltersDraft())
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: KWSpacing.md) {
                    KWFlowHeader(.close, action: onClose)
                    Text("Filters", bundle: #bundle)
                        .kwTextStyle(.titleSm)
                        .accessibilityAddTraits(.isHeader)
                    amountSection
                    originSection
                }
                .padding(.horizontal, KWLayout.gutter)
                .padding(.vertical, KWSpacing.xl)
            }
            .scrollIndicators(.hidden)
            Button {
                viewModel.apply(draft)
                onClose()
            } label: {
                Text("Apply", bundle: #bundle)
            }
            .buttonStyle(.kw())
            .disabled(!draft.canApply)
            .padding(.horizontal, KWLayout.gutter)
            .padding(.vertical, KWSpacing.sm)
        }
        .foregroundStyle(KWColor.Text.primary)
    }

    private var amountSection: some View {
        let symbol = CurrencyFormatter.symbol(for: viewModel.principalCurrency)
        return VStack(alignment: .leading, spacing: KWSpacing.xs) {
            KWSectionHeader(String(localized: "Amount", bundle: #bundle))
            KWGroupedCard(verticalPadding: KWSpacing.xxs) {
                KWAmountFieldRow(String(localized: "Minimum", bundle: #bundle), symbol: symbol, placeholder: "", text: $draft.minText)
                KWAmountFieldRow(String(localized: "Maximum", bundle: #bundle), symbol: symbol, placeholder: "", text: $draft.maxText)
            }
            if draft.isMinAboveMax {
                Text("Minimum is above maximum", bundle: #bundle)
                    .font(KWTextStyle.caption.font)
                    .foregroundStyle(KWColor.State.negative)
            } else if let note = viewModel.conversionNote {
                Text(note)
                    .font(KWTextStyle.caption.font)
                    .foregroundStyle(KWColor.Text.muted)
            }
        }
    }

    private var originSection: some View {
        VStack(alignment: .leading, spacing: KWSpacing.xs) {
            KWSectionHeader(String(localized: "Origin", bundle: #bundle))
            // A rule's list (opened from the rule) checks neither until one is picked.
            KWGroupedCard(verticalPadding: KWSpacing.xxs) {
                originRow(String(localized: "All", bundle: #bundle), origin: .any)
                originRow(String(localized: "Subscriptions only", bundle: #bundle), origin: .subscriptions)
            }
        }
    }

    private func originRow(_ title: String, origin: TransactionOrigin) -> some View {
        let isSelected = draft.origin == origin
        return Button { draft.origin = origin } label: {
            HStack(spacing: KWSpacing.sm) {
                Text(title)
                    .font(KWTextStyle.body.font)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if isSelected {
                    KWIconView(.check, size: 18)
                        .foregroundStyle(KWColor.Brand.link)
                }
            }
            .padding(.vertical, KWSpacing.sm)
            .frame(minHeight: KWLayout.minTouch)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
