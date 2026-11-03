import DesignSystem
import SharedPresentation
import SwiftUI

/// The green check that marks the chosen row.
struct SelectedCheck: View {
    var body: some View {
        KWIconView(.check, size: 14, lineWidth: 3)
            .foregroundStyle(KWColor.Text.onPositive)
            .frame(width: 24, height: 24)
            .background(KWColor.State.positive, in: Circle())
            .accessibilityLabel(Text("Selected", bundle: #bundle))
    }
}

/// An empty ring that fills with the check once chosen, for single-choice lists.
struct RadioIndicator: View {
    let isSelected: Bool

    var body: some View {
        if isSelected {
            SelectedCheck()
        } else {
            Circle()
                .strokeBorder(KWColor.Surface.controlOff, lineWidth: 2)
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)
        }
    }
}

/// The card, banknote or transfer tile standing for an account or payment method.
struct SourceThumbnail: View {
    let thumbnail: MethodRow.Thumbnail
    var size: KWMiniCard.Size = .small

    var body: some View {
        switch thumbnail {
        case let .card(color): KWMiniCard(.palette(CardDisplay.palette(for: color), chip: size == .medium), size: size)
        case .transfer: KWMiniCard(.transfer, size: size)
        case .cash: KWMiniCard(.solid(KWColor.State.positive), size: size)
        }
    }
}

/// A row card: a leading thumbnail, title, a muted detail, and whatever goes on the trailing edge.
struct AccountRowCard<Leading: View, Trailing: View>: View {
    let title: String
    let detail: String?
    var caption: String?
    @ViewBuilder let leading: () -> Leading
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: KWSpacing.sm) {
            leading()
            VStack(alignment: .leading, spacing: 2) {
                if let caption {
                    Text(caption).font(KWTextStyle.captionSm.font).foregroundStyle(KWColor.Text.muted)
                }
                Text(title).font(.kw(16, weight: 600)).lineLimit(1)
                if let detail {
                    Text(detail)
                        .font(KWTextStyle.label.font.weight(.regular))
                        .foregroundStyle(KWColor.Text.muted)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing()
        }
        .padding(.horizontal, KWSpacing.md)
        .padding(.vertical, 14)
        .background(KWColor.Surface.surface, in: RoundedRectangle(cornerRadius: KWRadius.surface, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: KWRadius.surface))
        .accessibilityElement(children: .combine)
    }
}

extension AccountRowCard where Leading == SourceThumbnail {
    init(
        thumbnail: MethodRow.Thumbnail,
        title: String,
        detail: String?,
        caption: String? = nil,
        @ViewBuilder trailing: @escaping () -> Trailing,
    ) {
        self.init(
            title: title,
            detail: detail,
            caption: caption,
            leading: { SourceThumbnail(thumbnail: thumbnail, size: .medium) },
            trailing: trailing,
        )
    }
}

/// The note, edited in a small sheet so the amount screen keeps its own keypad.
struct NoteSheet: View {
    @Binding var note: String
    let onDone: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: KWSpacing.md) {
            HStack {
                Text("Note", bundle: #bundle).kwTextStyle(.titleSm).accessibilityAddTraits(.isHeader)
                Spacer()
                Button(action: onDone) { Text("Done", bundle: #bundle) }
                    .buttonStyle(.kw(.primary, size: .small))
            }
            TextField(String(localized: "What was it about?", bundle: #bundle), text: $note)
                .font(KWTextStyle.body.font)
                .focused($isFocused)
                .submitLabel(.done)
                .onSubmit(onDone)
                .padding(KWSpacing.md)
                .background(KWColor.Surface.surface2, in: RoundedRectangle(cornerRadius: KWRadius.input))
            Spacer(minLength: 0)
        }
        .padding(KWLayout.gutter)
        .padding(.top, KWSpacing.xs)
        .foregroundStyle(KWColor.Text.primary)
        .presentationDetents([.height(220)])
        .presentationBackground(KWColor.Surface.surface)
        .onAppear { isFocused = true }
    }
}
