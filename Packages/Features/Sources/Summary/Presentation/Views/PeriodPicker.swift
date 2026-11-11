import DesignSystem
import Domain
import SummaryDomain
import SwiftUI

/// Month, This year, Last 12 months or Custom. Chips scroll sideways because four titles don't fit
/// the width of a phone at larger text sizes.
struct PeriodPicker: View {
    @Bindable var viewModel: SummaryViewModel

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: KWSpacing.xs) {
                ForEach(SummaryPeriod.allCases, id: \.self) { period in
                    KWChip(viewModel.title(of: period), isSelected: viewModel.period == period) {
                        viewModel.period = period
                    }
                }
            }
            .padding(.horizontal, KWLayout.gutter)
        }
        .scrollIndicators(.hidden)
        .padding(.horizontal, -KWLayout.gutter)
        .accessibilityLabel(Text("Period", bundle: #bundle))
    }
}

/// From and to, reaching back to the first movement; picking them in either order works.
struct CustomRangePicker: View {
    let viewModel: SummaryViewModel

    var body: some View {
        if let current = viewModel.range?.report.range {
            HStack(spacing: KWSpacing.sm) {
                picker(String(localized: "From", bundle: #bundle), selection: current.start) { viewModel.setCustomStart($0) }
                picker(
                    String(localized: "To", bundle: #bundle, comment: "End of a custom date range, as in 'From March To August'"),
                    selection: current.end,
                ) { viewModel.setCustomEnd($0) }
            }
        }
    }

    private func picker(_ title: String, selection: YearMonth, onChange: @escaping @MainActor (YearMonth) -> Void) -> some View {
        Menu {
            Picker(title, selection: Binding(get: { selection }, set: onChange)) {
                ForEach(viewModel.customMonthOptions, id: \.self) { month in
                    Text(viewModel.pickerTitle(of: month)).tag(month)
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(KWTextStyle.captionSm.font)
                    .foregroundStyle(KWColor.Text.muted)
                Text(viewModel.pickerTitle(of: selection))
                    .font(KWTextStyle.label.font)
                    .foregroundStyle(KWColor.Text.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(KWSpacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(KWColor.Surface.surface, in: RoundedRectangle(cornerRadius: KWRadius.surface, style: .continuous))
        }
        .accessibilityLabel(title)
        .accessibilityValue(viewModel.pickerTitle(of: selection))
    }
}
