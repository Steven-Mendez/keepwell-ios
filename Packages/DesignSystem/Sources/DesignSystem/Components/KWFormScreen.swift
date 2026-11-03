import SwiftUI

/// Screen for anything people type into: the content scrolls and the footer (the primary action)
/// stays pinned at the bottom, riding on top of the keyboard while it is up. `KWScreen` lets the
/// keyboard cover its lower part, which hid "Save" behind number pads that have no return key.
///
/// The content keeps `KWScreen`'s margins measured from the physical edges, scrolls the focused
/// field into view, and dragging it or tapping empty space hides the keyboard.
public struct KWFormScreen<Content: View, Footer: View>: View {
    private let top: CGFloat
    private let bottom: CGFloat
    private let horizontal: CGFloat
    private let content: Content
    private let footer: Footer

    /// Every safe-area inset, keyboard included.
    @State private var insets = EdgeInsets()
    /// The bottom inset without the keyboard (home indicator, sheet edge).
    @State private var containerBottom: CGFloat = 0
    @State private var viewport: CGFloat = 0
    @Environment(\.kwFocusedField) private var focusedField

    public init(
        top: CGFloat = KWLayout.safeTop,
        bottom: CGFloat = 34,
        horizontal: CGFloat = KWLayout.gutter,
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer,
    ) {
        self.top = top
        self.bottom = bottom
        self.horizontal = horizontal
        self.content = content()
        self.footer = footer()
    }

    public var body: some View {
        VStack(spacing: 0) {
            scroll
            VStack(spacing: KWSpacing.xs) { footer }
                .padding(.horizontal, horizontal)
                .padding(.top, KWSpacing.sm)
                .padding(.bottom, Self.footerBottomPadding(
                    bottom: bottom,
                    safeBottom: insets.bottom,
                    containerBottom: containerBottom,
                ))
        }
        .onGeometryChange(for: EdgeInsets.self) { $0.safeAreaInsets } action: { insets = $0 }
        .background {
            KWColor.Surface.bg.ignoresSafeArea()
            // Ignoring only the keyboard leaves the container inset, so comparing it with
            // `insets.bottom` tells whether the keyboard is up.
            Color.clear
                .ignoresSafeArea(.keyboard)
                .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.bottom } action: { containerBottom = $0 }
        }
        .foregroundStyle(KWColor.Text.primary)
    }

    private var scroll: some View {
        ScrollViewReader { proxy in
            scrollView
                // The system only keeps a focused field clear of the keyboard, not of the footer
                // or the field bar, so the form scrolls it fully into view itself.
                .onChange(of: focusedField) { _, field in
                    guard let field else { return }
                    // After the system's own adjustment for the new first responder, which would
                    // otherwise undo part of this scroll.
                    Task { @MainActor in
                        withAnimation(.snappy) { proxy.scrollTo(field) }
                    }
                }
        }
    }

    private var scrollView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) { content }
                .padding(.top, max(top - insets.top, 0))
                .padding(.bottom, KWSpacing.md)
                .padding(.horizontal, horizontal)
                .frame(maxWidth: .infinity, minHeight: viewport, alignment: .topLeading)
                .background {
                    // Fills the viewport so a tap anywhere outside a control hides the keyboard;
                    // controls sit above it and keep their own taps.
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { KWKeyboard.dismiss() }
                }
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .scrollBounceBehavior(.basedOnSize)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { viewport = $0 }
    }

    /// With the keyboard up the footer keeps a small gap above it, as Revolut's "Continue" does;
    /// otherwise it sits `bottom` points above the physical edge, never under the home indicator.
    static func footerBottomPadding(bottom: CGFloat, safeBottom: CGFloat, containerBottom: CGFloat) -> CGFloat {
        let isKeyboardUp = safeBottom > containerBottom + 1
        return isKeyboardUp ? KWSpacing.sm : max(bottom - containerBottom, 0)
    }
}

extension EnvironmentValues {
    /// The field with focus in the enclosing `kwKeyboardToolbar`, for `KWFormScreen` to scroll to.
    @Entry var kwFocusedField: AnyHashable?
}
