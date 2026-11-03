import Core
import DesignSystem
import SharedPresentation
import SwiftUI

/// Step 2 · Category. For transfers the step picks the destination account instead.
public struct CategoryView: View {
    @Bindable private var viewModel: CreateTransactionViewModel
    private let onBack: () -> Void

    public init(viewModel: CreateTransactionViewModel, onBack: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onBack = onBack
    }

    public var body: some View {
        KWScreen(bottom: 34) {
            VStack(alignment: .leading, spacing: KWSpacing.md) {
                KWFlowHeader(.back, progress: (4, 2), action: onBack)
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .kwTextStyle(.titleSm)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    Text(viewModel.amountSummary)
                        .font(KWTextStyle.heading.font)
                        .monospacedDigit()
                }
                if viewModel.kind == .transfer {
                    destinations
                } else {
                    categories
                }
            }
        }
    }

    private var title: String {
        viewModel.kind == .transfer
            ? String(localized: "Where is it going?", bundle: #bundle)
            : String(localized: "What was it for?", bundle: #bundle)
    }

    private var seeAllTitle: String {
        let count = viewModel.categories.count
        return String(localized: "See all \(count)", bundle: #bundle)
    }

    private var categories: some View {
        VStack(alignment: .leading, spacing: KWSpacing.md) {
            HStack(spacing: KWSpacing.xs) {
                KWIconView(.search, size: 18)
                TextField(String(localized: "Search category", bundle: #bundle), text: $viewModel.categoryQuery)
                    .font(KWTextStyle.body.font)
                    .foregroundStyle(KWColor.Text.primary)
            }
            .foregroundStyle(KWColor.Text.muted)
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(KWColor.Surface.surface, in: Capsule())
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                    ForEach(viewModel.visibleCategories) { category in
                        let isSelected = category.id == viewModel.categoryID
                        tile(CategoryDisplay.icon(for: category.id), CategoryDisplay.name(of: category), isSelected: isSelected) {
                            viewModel.selectCategory(category.id)
                        }
                    }
                    if viewModel.hasMoreCategories {
                        tile(.moreFilled, seeAllTitle, isSelected: false) {
                            viewModel.showsAllCategories = true
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.immediately)
        }
    }

    private var destinations: some View {
        KWGroupedCard(horizontalPadding: 14) {
            ForEach(viewModel.destinationOptions) { account in
                Button { viewModel.selectDestination(account.id) } label: {
                    HStack {
                        KWTitleSubtitle(CardDisplay.name(of: account), subtitle: viewModel.balanceLabel(of: account))
                        Spacer()
                        if account.id == viewModel.destinationAccountID {
                            SelectedCheck()
                        }
                    }
                    .padding(.vertical, KWSpacing.sm)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func tile(_ icon: KWIcon, _ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: KWSpacing.xs) {
                KWIconView(icon, size: 26)
                Text(title)
                    .font(.kw(13, weight: isSelected ? 700 : 600, relativeTo: .footnote))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(isSelected ? Color.black : KWColor.Text.primary)
            .frame(maxWidth: .infinity)
            .frame(height: 96)
            .background(isSelected ? Color.white : KWColor.Surface.surface, in: RoundedRectangle(cornerRadius: KWRadius.card))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// The green check that marks the chosen row.
struct SelectedCheck: View {
    var body: some View {
        KWIconView(.check, size: 14, lineWidth: 3)
            .foregroundStyle(KWColor.Text.onPositive)
            .frame(width: 24, height: 24)
            .background(KWColor.State.positive, in: Circle())
            .accessibilityLabel(Text("Selected", bundle: #bundle))
    }
}
