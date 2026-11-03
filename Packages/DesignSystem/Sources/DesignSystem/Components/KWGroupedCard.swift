import SwiftUI

/// The rounded `surface` card that groups rows, with a divider between each pair of rows, as in
/// every list of the design. Rows stay free of divider logic.
public struct KWGroupedCard<Content: View>: View {
    private let horizontalPadding: CGFloat
    private let verticalPadding: CGFloat
    private let content: Content

    public init(
        horizontalPadding: CGFloat = KWSpacing.md,
        verticalPadding: CGFloat = 2,
        @ViewBuilder content: () -> Content,
    ) {
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
        self.content = content()
    }

    public var body: some View {
        VStack(spacing: 0) {
            Group(subviews: content) { subviews in
                ForEach(subviews.indices, id: \.self) { index in
                    subviews[index].frame(maxWidth: .infinity, alignment: .leading)
                    if index < subviews.count - 1 {
                        KWDivider()
                    }
                }
            }
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(KWColor.Surface.surface, in: RoundedRectangle(cornerRadius: KWRadius.surface, style: .continuous))
    }
}

/// 1pt `divider` line between rows.
public struct KWDivider: View {
    public init() {}

    public var body: some View {
        Rectangle()
            .fill(KWColor.Surface.divider)
            .frame(height: 1)
    }
}
