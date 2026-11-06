import DesignSystem
import SwiftUI

/// Step 7 · Done.
public struct DoneView: View {
    private let viewModel: OnboardingViewModel
    private let onLogFirstExpense: () -> Void
    private let onGoHome: () -> Void

    public init(viewModel: OnboardingViewModel, onLogFirstExpense: @escaping () -> Void, onGoHome: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onLogFirstExpense = onLogFirstExpense
        self.onGoHome = onGoHome
    }

    public var body: some View {
        KWScreen(top: 140, bottom: 40, horizontal: 20) {
            KWGlowBackground(.success)
        } content: {
            VStack(spacing: 0) {
                KWIconView(.check, size: 44, lineWidth: 2.6)
                    .foregroundStyle(KWColor.Text.onPositive)
                    .frame(width: 88, height: 88)
                    .background(KWColor.State.positive, in: Circle())
                Text(viewModel.doneTitle)
                    .kwTextStyle(.title)
                    .padding(.top, 28)
                    .padding(.bottom, 10)
                    .accessibilityAddTraits(.isHeader)
                Text("Now log your first transaction. The more you record, the better your monthly summary.", bundle: #bundle)
                    .font(.kw(17, weight: 400))
                    .foregroundStyle(KWColor.Text.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                summary
                    .padding(.top, 28)
                Spacer(minLength: KWSpacing.md)
                Button(action: onLogFirstExpense) { Text("Log first expense", bundle: #bundle) }
                    .buttonStyle(.kw())
                Button(action: onGoHome) { Text("Go to home", bundle: #bundle) }
                    .buttonStyle(.kw(.plain, size: .text))
                    .padding(.top, KWSpacing.xs)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var summary: some View {
        VStack(spacing: 0) {
            Group(subviews: rows) { subviews in
                ForEach(subviews.indices, id: \.self) { index in
                    subviews[index]
                    if index < subviews.count - 1 {
                        KWDivider()
                    }
                }
            }
        }
        .padding(.horizontal, KWSpacing.md)
        .padding(.vertical, KWSpacing.xxs)
        .background(KWColor.Overlay.surfaceTranslucent, in: RoundedRectangle(cornerRadius: KWRadius.surface))
    }

    @ViewBuilder
    private var rows: some View {
        KWValueRow(String(localized: "Currencies", bundle: #bundle), value: viewModel.currenciesSummary)
        if let rate = viewModel.rateSummary {
            KWValueRow(String(localized: "Rate", bundle: #bundle), value: rate)
        }
        KWValueRow(String(localized: "Accounts", bundle: #bundle), value: "\(viewModel.accounts.count)")
    }
}
