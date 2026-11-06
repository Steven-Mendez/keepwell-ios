import DesignSystem
import SwiftUI

/// The palette colors as a grid of swatches. Shared by the category editor and anything else
/// people tint the same way (savings goals), so both offer exactly the same colors.
public struct CategoryColorPicker: View {
    @Binding private var selection: String?

    public init(selection: Binding<String?>) {
        _selection = selection
    }

    public var body: some View {
        // Two rows of five, so every color and the selected one stay in view.
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: KWSpacing.xs), count: 5), spacing: KWSpacing.xs) {
            ForEach(CategoryDisplay.colorChoices, id: \.self) { key in
                let isSelected = key == selection
                Button { selection = key } label: {
                    Circle()
                        .fill(KWColor.categoryPalette(key: key) ?? KWColor.Text.faint)
                        .frame(width: 36, height: 36)
                        .padding(3)
                        .overlay(Circle().strokeBorder(isSelected ? Color.white : .clear, lineWidth: 2))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(CategoryDisplay.colorName(key))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }
}

/// `CategoryDisplay.symbolChoices` as a grid of icons, for categories and savings goals alike.
public struct CategorySymbolPicker: View {
    @Binding private var selection: String

    public init(selection: Binding<String>) {
        _selection = selection
    }

    public var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: KWSpacing.xs), count: 6), spacing: KWSpacing.xs) {
            ForEach(CategoryDisplay.symbolChoices, id: \.self) { symbol in
                let isSelected = symbol == selection
                Button { selection = symbol } label: {
                    CategorySymbol(symbol: symbol, size: 22)
                        .foregroundStyle(isSelected ? Color.black : KWColor.Text.primary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(isSelected ? Color.white : KWColor.Surface.surface, in: RoundedRectangle(cornerRadius: 12))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(verbatim: symbol))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }
}
