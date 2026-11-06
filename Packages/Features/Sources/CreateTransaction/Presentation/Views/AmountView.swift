import DesignSystem
import Domain
import SwiftUI

/// The amount, typed on the app's own keypad so the system keyboard never covers the button.
/// Under it: what the source has available, any conversion, and the note.
public struct AmountView: View {
    @Bindable private var viewModel: CreateTransactionViewModel
    private let onBack: () -> Void
    @State private var isEditingNote = false

    public init(viewModel: CreateTransactionViewModel, onBack: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onBack = onBack
    }

    public var body: some View {
        KWScreen(bottom: 34) {
            VStack(spacing: KWSpacing.md) {
                KWFlowHeader(
                    viewModel.rootStep == .amount ? .close : .back,
                    progress: viewModel.progress(of: .amount),
                    action: onBack,
                )
                Spacer(minLength: 0)
                summary
                Spacer(minLength: 0)
                keypad
                Button { viewModel.continueFromAmount() } label: { Text(viewModel.amountButtonTitle) }
                    .buttonStyle(.kw())
                    .disabled(!viewModel.canContinueFromAmount)
            }
        }
        .sheet(isPresented: $isEditingNote) {
            NoteSheet(note: $viewModel.note) { isEditingNote = false }
        }
    }

    private var summary: some View {
        VStack(spacing: KWSpacing.sm) {
            Text(viewModel.amountQuestion)
                .font(.kw(22, weight: 700, relativeTo: .title2))
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text(viewModel.amountDisplay)
                .font(.kw(56, weight: 800, relativeTo: .largeTitle))
                .tracking(-2)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .contentTransition(.numericText())
                .animation(.snappy(duration: 0.2), value: viewModel.amountText)
                .accessibilityLabel(amountAccessibilityLabel)
            if viewModel.currencyOptions.count > 1 {
                KWSegmentedControl(
                    viewModel.currencyOptions.map { (value: $0, title: $0) },
                    selection: $viewModel.currency,
                    style: .accent,
                )
                .frame(width: 160)
            }
            if let available = availableText {
                Text(available)
                    .font(KWTextStyle.label.font.weight(.regular))
                    .foregroundStyle(viewModel.exceedsAvailable ? KWColor.State.pending : KWColor.Text.muted)
                    .monospacedDigit()
                    .multilineTextAlignment(.center)
            }
            if let conversion = viewModel.conversionLine {
                Text(conversion)
                    .font(KWTextStyle.captionSm.font)
                    .foregroundStyle(KWColor.Text.muted)
                    .monospacedDigit()
                    .multilineTextAlignment(.center)
            }
            notePill
        }
        .frame(maxWidth: .infinity)
    }

    /// "Debit •••• 1234 · Available $9,520.00", with a warning when the amount is larger.
    private var availableText: String? {
        guard let available = viewModel.availableLabel else { return nil }
        if viewModel.exceedsAvailable {
            return String(localized: "\(available) · more than what's there", bundle: #bundle)
        }
        if viewModel.kind == .expense, let method = viewModel.sourceTitle {
            return "\(method) · \(available)"
        }
        return available
    }

    private var notePill: some View {
        Button { isEditingNote = true } label: {
            HStack(spacing: 6) {
                KWIconView(.pencil, size: 15, lineWidth: 2)
                Text(viewModel.notePillTitle)
                    .font(.kw(14, weight: 600, relativeTo: .subheadline))
                    .lineLimit(1)
            }
            .foregroundStyle(KWColor.Brand.link)
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background(KWColor.Surface.surface, in: Capsule())
        }
        .buttonStyle(.plain)
        .padding(.top, KWSpacing.xxs)
    }

    private var amountAccessibilityLabel: String {
        let display = viewModel.amountDisplay
        return String(localized: "Amount \(display)", bundle: #bundle)
    }

    private var keypad: some View {
        let keys: [CreateTransactionViewModel.Key] = (1 ... 9).map { .digit($0) } + [.dot, .digit(0), .delete]
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: KWSpacing.xs), count: 3), spacing: KWSpacing.xxs) {
            ForEach(keys, id: \.self) { key in
                Button { viewModel.press(key) } label: { keyLabel(key) }
                    .buttonStyle(KeypadKeyStyle())
                    .accessibilityLabel(key == .delete ? String(localized: "Delete", bundle: #bundle) : label(key))
            }
        }
        .sensoryFeedback(.impact(weight: .light, intensity: 0.6), trigger: viewModel.amountText)
    }

    @ViewBuilder
    private func keyLabel(_ key: CreateTransactionViewModel.Key) -> some View {
        if key == .delete {
            KWIconView(.chevronLeft, size: 24, lineWidth: 2.4)
        } else {
            Text(label(key)).font(.kw(30, weight: 600))
        }
    }

    private func label(_ key: CreateTransactionViewModel.Key) -> String {
        switch key {
        case let .digit(value): "\(value)"
        case .dot: "."
        case .delete: "⌫"
        }
    }
}

/// Large keys without tiles, as a phone dialer: the press shows a soft highlight.
private struct KeypadKeyStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(KWColor.Text.primary)
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            .background(
                configuration.isPressed ? KWColor.Surface.surface2 : Color.clear,
                in: RoundedRectangle(cornerRadius: KWSpacing.md),
            )
            .contentShape(Rectangle())
    }
}
