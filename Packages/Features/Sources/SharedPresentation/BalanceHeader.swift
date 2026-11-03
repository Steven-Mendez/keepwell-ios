import DesignSystem
import Domain
import SwiftUI

/// A bank screen's headline balance, LAFISE-style: a small label, the amount big, and an eye that
/// hides it. The choice is shared by every account and card screen and kept between launches,
/// because someone hiding their balance in public wants it hidden on the next screen too.
public struct BalanceHeader: View {
    public static let hidesBalanceKey = "kw.hidesBalance"

    private let label: String
    private let amount: String
    private let details: [String]
    private let alignment: HorizontalAlignment
    @AppStorage(Self.hidesBalanceKey) private var isHidden = false

    /// `details` are smaller per-currency pills under the amount (a dual credit card's debts).
    public init(_ label: String, amount: String, details: [String] = [], alignment: HorizontalAlignment = .center) {
        self.label = label
        self.amount = amount
        self.details = details
        self.alignment = alignment
    }

    private static let mask = "••••••"

    public var body: some View {
        VStack(alignment: alignment, spacing: KWSpacing.xxs) {
            Text(label)
                .font(KWTextStyle.label.font.weight(.regular))
                .foregroundStyle(KWColor.Text.onBrand)
            HStack(spacing: KWSpacing.xxs) {
                Text(isHidden ? Self.mask : amount)
                    .kwTextStyle(.amountLg)
                    .tracking(-1.2)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .contentTransition(.opacity)
                    .accessibilityLabel(isHidden ? Text("Hidden balance", bundle: #bundle) : Text(amount))
                Button { isHidden.toggle() } label: {
                    Image(systemName: isHidden ? "eye" : "eye.slash")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(KWColor.Text.onBrand)
                        .frame(width: KWLayout.minTouch, height: KWLayout.minTouch)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isHidden ? Text("Show balance", bundle: #bundle) : Text("Hide balance", bundle: #bundle))
            }
            if !details.isEmpty {
                HStack(spacing: 6) {
                    ForEach(details, id: \.self) { detail in
                        Text(isHidden ? Self.mask : detail)
                            .font(.kw(13, weight: 600, relativeTo: .footnote))
                            .monospacedDigit()
                            .padding(.horizontal, 10)
                            .frame(height: 26)
                            .background(KWColor.Overlay.white14, in: Capsule())
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: Alignment(horizontal: alignment, vertical: .center))
        .animation(.snappy, value: isHidden)
    }
}

/// A short list of an account's or card's latest movements with "See all", which opens the full,
/// filtered list.
public struct LatestMovementsSection<Row: View>: View {
    private let title: String
    private let transactions: [Domain.Transaction]
    private let emptyMessage: String
    private let onSeeAll: (() -> Void)?
    private let row: (Domain.Transaction) -> Row

    public init(
        _ title: String,
        transactions: [Domain.Transaction],
        emptyMessage: String,
        onSeeAll: (() -> Void)?,
        @ViewBuilder row: @escaping (Domain.Transaction) -> Row,
    ) {
        self.title = title
        self.transactions = transactions
        self.emptyMessage = emptyMessage
        self.onSeeAll = onSeeAll
        self.row = row
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: KWSpacing.md) {
            KWSectionHeader(title, style: .large) {
                if let onSeeAll {
                    Button(action: onSeeAll) {
                        Text("See all", bundle: #bundle)
                            .font(KWTextStyle.label.font)
                            .foregroundStyle(KWColor.Brand.link)
                            .frame(minHeight: KWLayout.minTouch)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, -KWSpacing.sm)
            KWGroupedCard(verticalPadding: KWSpacing.xxs) {
                if transactions.isEmpty {
                    Text(emptyMessage)
                        .font(KWTextStyle.body.font)
                        .foregroundStyle(KWColor.Text.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, KWSpacing.md)
                } else {
                    ForEach(transactions) { transaction in
                        row(transaction)
                    }
                }
            }
        }
    }
}
