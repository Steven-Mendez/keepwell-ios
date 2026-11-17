import DesignSystem
import Domain
import SharedPresentation
import SwiftUI

/// "Link to a recurring": the rules a movement could be a payment of. Choosing one links it and
/// closes the sheet; the movement then counts as that rule's payment.
public struct RecurringRulePickerSheet: View {
    private let viewModel: RecurringRulePickerViewModel
    private let onDone: () -> Void

    public init(viewModel: RecurringRulePickerViewModel, onDone: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onDone = onDone
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KWSpacing.sm) {
                Text("Link to a recurring", bundle: #bundle)
                    .kwTextStyle(.titleSm)
                    .accessibilityAddTraits(.isHeader)
                Text("It counts as a payment of the one you choose.", bundle: #bundle)
                    .font(KWTextStyle.caption.font)
                    .foregroundStyle(KWColor.Text.muted)
                if let error = viewModel.actionError {
                    Text(error)
                        .font(KWTextStyle.caption.font)
                        .foregroundStyle(KWColor.State.negative)
                }
                content
            }
            .padding(KWLayout.gutter)
            .padding(.top, KWSpacing.xs)
        }
        .scrollIndicators(.hidden)
        .foregroundStyle(KWColor.Text.primary)
        .task { await viewModel.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            ProgressView().frame(maxWidth: .infinity).padding(.top, KWSpacing.lg)
        case .failed:
            Text("We couldn't load your recurring payments.", bundle: #bundle)
                .foregroundStyle(KWColor.Text.muted)
        case .loaded:
            if viewModel.rules.isEmpty {
                Text("No recurring payments of this kind", bundle: #bundle)
                    .foregroundStyle(KWColor.Text.muted)
            } else {
                KWGroupedCard {
                    ForEach(viewModel.rules) { rule in
                        Button {
                            Task {
                                if await viewModel.link(to: rule) {
                                    onDone()
                                }
                            }
                        } label: {
                            HStack(spacing: KWSpacing.sm) {
                                RecurringChoiceRow(title: rule.name, subtitle: viewModel.subtitle(of: rule)) {
                                    icon(rule)
                                }
                            }
                            .padding(.vertical, KWSpacing.sm)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(viewModel.isWorking)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func icon(_ rule: RecurringRule) -> some View {
        if rule.kind == .transfer {
            KWTransactionIcon(.transfer)
        } else {
            let category = viewModel.category(of: rule)
            BrandOrFallbackIcon(text: rule.name, tint: CategoryDisplay.color(for: category)) {
                CategorySymbol(category, size: 18)
                    .foregroundStyle(CategoryDisplay.color(for: category))
                    .frame(width: 40, height: 40)
                    .background(CategoryDisplay.color(for: category).opacity(0.16), in: Circle())
                    .accessibilityHidden(true)
            }
        }
    }
}
