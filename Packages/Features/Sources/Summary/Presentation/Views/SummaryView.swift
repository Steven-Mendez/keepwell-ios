import Charts
import Core
import DesignSystem
import Domain
import SharedPresentation
import SwiftUI

/// Monthly summary as three charts behind one switch: cash flow (did I save?), categories (where
/// did it go?) and pace (am I spending faster than last month?). A month stepper drives all three.
public struct SummaryView: View {
    @Bindable private var viewModel: SummaryViewModel
    private let onEditBudgets: () -> Void
    private let onNewMovement: () -> Void

    public init(viewModel: SummaryViewModel, onEditBudgets: @escaping () -> Void, onNewMovement: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onEditBudgets = onEditBudgets
        self.onNewMovement = onNewMovement
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KWSpacing.md) {
                KWLargeTitleHeader(String(localized: "Summary", bundle: #bundle)) {
                    EmptyView()
                }
                if viewModel.report != nil, !viewModel.hasMovements {
                    KWEmptyState(
                        icon: .chartBars,
                        title: String(localized: "Your summary starts with one transaction", bundle: #bundle),
                        message: viewModel.emptyMessage,
                        actionTitle: String(localized: "Log transaction", bundle: #bundle),
                        action: onNewMovement,
                    )
                    .padding(.top, 120)
                } else if viewModel.report != nil {
                    content
                }
            }
            .padding(.horizontal, KWLayout.gutter)
            .padding(.top, KWLayout.safeTop)
            .padding(.bottom, KWSpacing.lg)
            .animation(.snappy, value: viewModel.chart)
            .animation(.snappy, value: viewModel.mode)
            .animation(.snappy, value: viewModel.selectedIndex)
            .animation(.snappy, value: viewModel.period)
        }
        .scrollIndicators(.hidden)
        .ignoresSafeArea(edges: .top)
        .background(KWColor.Surface.bg)
        .foregroundStyle(KWColor.Text.primary)
        .task { await viewModel.load() }
        .task(id: viewModel.rangeRequest) { await viewModel.loadRange() }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.getRange != nil {
            PeriodPicker(viewModel: viewModel)
        }
        if viewModel.showsRange {
            if viewModel.period == .custom {
                CustomRangePicker(viewModel: viewModel)
            }
            if viewModel.range != nil {
                RangeSection(viewModel: viewModel)
                // The web ends range mode with it too; pace stays a month-only chart.
                NetWorthSection(viewModel: viewModel)
                    .padding(.top, KWSpacing.xs)
            }
        } else {
            KWSegmentedControl(
                SummaryViewModel.Chart.allCases.map { (value: $0, title: viewModel.title(of: $0)) },
                selection: $viewModel.chart,
            )
            monthStepper
            switch viewModel.chart {
            case .cashFlow: CashFlowSection(viewModel: viewModel)
            case .categories: CategorySection(viewModel: viewModel, onEditBudgets: onEditBudgets)
            case .pace: PaceSection(viewModel: viewModel)
            }
            // A year of month ends, whatever month the stepper picks.
            NetWorthSection(viewModel: viewModel)
                .padding(.top, KWSpacing.xs)
        }
    }

    /// Tapping a bar also picks a month, but the categories and pace charts have no bars, and
    /// VoiceOver needs a control that works the same on every chart.
    private var monthStepper: some View {
        HStack(spacing: KWSpacing.xs) {
            stepButton(.chevronLeft, label: String(localized: "Previous month", bundle: #bundle), enabled: viewModel.canSelectPrevious) {
                viewModel.selectPrevious()
            }
            Text(viewModel.selectedMonthTitle)
                .font(KWTextStyle.heading.font)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
                .contentTransition(.numericText())
                .accessibilityAddTraits(.isHeader)
            stepButton(.chevronRight, label: String(localized: "Next month", bundle: #bundle), enabled: viewModel.canSelectNext) {
                viewModel.selectNext()
            }
        }
    }

    private func stepButton(_ icon: KWIcon, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            KWIconView(icon, size: 16)
                .frame(width: 36, height: 36)
                .background(KWColor.Surface.surface, in: Circle())
                .opacity(enabled ? 1 : 0.35)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }
}

extension SummaryViewModel.Tone {
    var color: Color {
        switch self {
        case .positive: KWColor.State.positive
        case .negative: KWColor.State.negative
        case .neutral: KWColor.Text.secondary
        }
    }

    var tint: Color {
        switch self {
        case .positive: KWColor.Tint.positive
        case .negative: KWColor.Tint.negative
        case .neutral: KWColor.Surface.surface2
        }
    }
}

/// A rounded dark card, the container every chart section sits in.
struct SummaryCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(KWSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(KWColor.Surface.surface, in: RoundedRectangle(cornerRadius: KWRadius.surface, style: .continuous))
    }
}

/// A tinted capsule carrying a short verdict ("You kept 60% of what came in").
struct SummaryPill: View {
    let text: String
    let tone: SummaryViewModel.Tone

    var body: some View {
        Text(text)
            .font(.kw(13, weight: 700, relativeTo: .footnote))
            .foregroundStyle(tone.color)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, KWSpacing.sm)
            .padding(.vertical, 6)
            .background(tone.tint, in: Capsule())
    }
}

/// Axis names VoiceOver reads when it describes a chart.
enum ChartAxis {
    static let month = String(localized: "Month", bundle: #bundle)
    static let day = String(localized: "Day", bundle: #bundle)
    static let amount = String(localized: "Amount", bundle: #bundle)
    static let result = String(localized: "Result", bundle: #bundle)
    static let direction = String(localized: "Direction", bundle: #bundle)
}

/// Three gridlines labelled in whole units of the principal currency, on the trailing edge. The
/// axis builds its labels outside the main actor, so it takes the currency, not the view model.
func moneyAxis(currency: String) -> some AxisContent {
    let formatter = CurrencyFormatter()
    return AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
        AxisGridLine().foregroundStyle(KWColor.Surface.divider)
        AxisValueLabel {
            if let amount = value.as(Double.self) {
                Text(formatter.string(from: Decimal(amount), currencyCode: currency, fractionDigits: 0))
                    .font(.kw(11, weight: 500, relativeTo: .caption2))
                    .foregroundStyle(KWColor.Text.faint)
            }
        }
    }
}
