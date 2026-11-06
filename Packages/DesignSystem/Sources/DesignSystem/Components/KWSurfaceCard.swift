import SwiftUI

public struct KWSurfaceCard<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .padding(KWSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(KWColor.Surface.surface, in: RoundedRectangle(cornerRadius: KWRadius.surface, style: .continuous))
    }
}

#Preview {
    KWSurfaceCard {
        Text("Surface").kwTextStyle(.body).foregroundStyle(KWColor.Text.primary)
    }
    .padding(KWLayout.gutter)
    .background(KWColor.Surface.bg)
    .onAppear { KWFonts.register() }
}
