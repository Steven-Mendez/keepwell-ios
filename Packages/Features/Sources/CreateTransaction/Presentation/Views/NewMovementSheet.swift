import CreateTransactionDomain
import DesignSystem
import SwiftUI

/// "What are you recording?": the entry to the flow, one row per kind of movement.
public struct NewMovementSheet: View {
    private let viewModel: NewMovementMenuViewModel
    private let onSelect: (MovementType) -> Void
    private let onClose: () -> Void

    public init(viewModel: NewMovementMenuViewModel, onSelect: @escaping (MovementType) -> Void, onClose: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onSelect = onSelect
        self.onClose = onClose
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: KWSpacing.xs) {
            HStack {
                Text("What are you recording?", bundle: #bundle)
                    .kwTextStyle(.titleSm)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                KWCircleButton(.close, accessibilityLabel: String(localized: "Close", bundle: #bundle), action: onClose)
            }
            .padding(.bottom, KWSpacing.xs)
            ForEach(viewModel.options) { option in
                Button { onSelect(option.type) } label: { row(option) }
                    .buttonStyle(MenuRowStyle())
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, KWLayout.gutter)
        .padding(.top, KWSpacing.lg)
        .foregroundStyle(KWColor.Text.primary)
        .task { await viewModel.load() }
    }

    private func row(_ option: NewMovementMenuViewModel.Option) -> some View {
        HStack(spacing: 14) {
            KWIconView(Self.icon(of: option.type), size: 22)
                .foregroundStyle(Self.tint(of: option.type))
                .frame(width: 48, height: 48)
                .background(Self.tint(of: option.type).opacity(0.16), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(option.title).font(.kw(16, weight: 600))
                Text(option.subtitle).font(KWTextStyle.captionSm.font).foregroundStyle(KWColor.Text.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            KWIconView(.chevronRight, size: 18).foregroundStyle(KWColor.Text.muted)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    static func icon(of type: MovementType) -> KWIcon {
        switch type {
        case .expense: .arrowUpRight
        case .income: .arrowDownLeft
        case .transfer: .transfer
        case .withdrawal: .cash
        case .cardPayment: .creditCard
        }
    }

    /// The colors movements already wear in lists: spending red, income green, transfers blue.
    static func tint(of type: MovementType) -> Color {
        switch type {
        case .expense: KWColor.State.negative
        case .income: KWColor.State.positive
        case .transfer, .cardPayment: KWColor.State.transfer
        case .withdrawal: KWColor.State.extra
        }
    }
}

private struct MenuRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.6 : 1)
    }
}
