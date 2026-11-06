import DesignSystem
import Domain
import SwiftUI

/// A savings goal's badge: its icon and palette color, drawn the same on the goals screen and home.
public enum SavingsGoalDisplay {
    /// What a goal shows before the person picks an icon.
    public static let defaultSymbol = "banknote"

    public static func symbol(for goal: SavingsGoal) -> String {
        goal.icon ?? defaultSymbol
    }

    public static func color(for goal: SavingsGoal) -> Color {
        goal.color.flatMap(KWColor.categoryPalette(key:)) ?? KWColor.Brand.accent
    }
}

/// The goal's icon on a tinted circle.
public struct SavingsGoalBadge: View {
    private let symbol: String
    private let tint: Color
    private let size: CGFloat

    public init(_ goal: SavingsGoal, size: CGFloat = 40) {
        symbol = SavingsGoalDisplay.symbol(for: goal)
        tint = SavingsGoalDisplay.color(for: goal)
        self.size = size
    }

    public init(symbol: String, tint: Color, size: CGFloat = 40) {
        self.symbol = symbol
        self.tint = tint
        self.size = size
    }

    public var body: some View {
        CategorySymbol(symbol: symbol, size: size * 0.45)
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.16), in: Circle())
            .accessibilityHidden(true)
    }
}
