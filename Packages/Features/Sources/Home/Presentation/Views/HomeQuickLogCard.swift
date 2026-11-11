import DesignSystem
import Domain
import HomeDomain
import SharedPresentation
import SwiftUI

/// The expense categories used most, one tap each to start an expense already in that category.
struct HomeQuickLogCard: View {
    let viewModel: HomeViewModel
    let overview: HomeOverview
    let onLog: (String) -> Void

    var body: some View {
        let categories = viewModel.quickLogCategories(overview)
        if !categories.isEmpty {
            VStack(alignment: .leading, spacing: KWSpacing.sm) {
                Text("Log quickly", bundle: #bundle)
                    .font(KWTextStyle.heading.font)
                    .accessibilityAddTraits(.isHeader)
                KWFlowLayout {
                    ForEach(categories, id: \.id) { category in
                        KWChip(
                            CategoryDisplay.name(of: category),
                            isSelected: false,
                            height: 32,
                            leading: CategoryBadge(category, size: 24),
                        ) { onLog(category.id) }
                            // "Expense · Restaurants", as the web chip's title: says what the tap
                            // starts, and keeps it apart from the category buttons in the sheet.
                            .accessibilityLabel(
                                "\(String(localized: "Expense", bundle: #bundle)) · \(CategoryDisplay.name(of: category))",
                            )
                    }
                }
            }
            .padding(KWSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(KWColor.Surface.surface, in: RoundedRectangle(cornerRadius: KWRadius.surface, style: .continuous))
        }
    }
}
