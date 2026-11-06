import DesignSystem
import Domain
import SwiftUI

/// How tags read on screen: "#viaje-méxico", the way people type them.
public enum TagDisplay {
    public static func label(_ tag: String) -> String {
        "#" + tag
    }

    /// "#boda #viaje", for a row's subtitle.
    public static func line(_ tags: [String]) -> String? {
        tags.isEmpty ? nil : tags.map(label).joined(separator: " ")
    }
}

/// A tag as a pill. With `onRemove` it carries an ×, as in the editors.
public struct TagChip: View {
    private let tag: String
    private let onTap: (() -> Void)?
    private let onRemove: (() -> Void)?

    public init(_ tag: String, onTap: (() -> Void)? = nil, onRemove: (() -> Void)? = nil) {
        self.tag = tag
        self.onTap = onTap
        self.onRemove = onRemove
    }

    public var body: some View {
        HStack(spacing: 6) {
            Text(TagDisplay.label(tag))
                .font(KWTextStyle.label.font)
                .lineLimit(1)
            if let onRemove {
                Button(action: onRemove) {
                    KWIconView(.close, size: 12, lineWidth: 2)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Remove \(TagDisplay.label(tag))", bundle: #bundle))
            }
        }
        .foregroundStyle(KWColor.Text.primary)
        .padding(.leading, 12)
        .padding(.trailing, onRemove == nil ? 12 : 6)
        .frame(height: 32)
        .background(KWColor.Surface.surface2, in: Capsule())
        .contentShape(Capsule())
        .onTapGesture { onTap?() }
    }
}

/// Adds and removes tags as "#chips": type one and press return, or pick one already used (most
/// used first). Tags are normalized as they're added, so "#Viaje México" becomes "#viaje-méxico".
public struct TagEditor: View {
    @Binding private var tags: [String]
    private let usage: [String]
    @State private var text = ""
    @FocusState private var isFocused: Bool

    public init(tags: Binding<[String]>, usage: [String]) {
        _tags = tags
        self.usage = usage
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: KWSpacing.xs) {
            if !tags.isEmpty {
                chips(tags) { tag in
                    TagChip(tag) { tags.removeAll { $0 == tag } }
                }
            }
            HStack(spacing: KWSpacing.xs) {
                Text(verbatim: "#").font(.kw(15, weight: 600)).foregroundStyle(KWColor.Text.muted)
                TextField(
                    String(localized: "Add a tag", bundle: #bundle),
                    text: $text,
                    prompt: Text("Add a tag", bundle: #bundle).foregroundStyle(KWColor.Text.muted),
                )
                .font(KWTextStyle.body.font)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused($isFocused)
                .onSubmit(add)
                if Tags.normalized(text) != nil {
                    Button(action: add) {
                        Text("Add", bundle: #bundle).font(KWTextStyle.label.font)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(KWColor.Brand.link)
                }
            }
            .padding(.vertical, KWSpacing.xs)
            let suggestions = Tags.suggestions(from: usage, typing: text, excluding: tags, limit: 6)
            if !suggestions.isEmpty {
                chips(suggestions) { tag in
                    TagChip(tag, onTap: { tags = Tags.merging(tags, with: [tag]) })
                        .foregroundStyle(KWColor.Text.secondary)
                        .accessibilityAddTraits(.isButton)
                        .accessibilityHint(Text("Adds the tag", bundle: #bundle))
                }
            }
        }
        .padding(.vertical, KWSpacing.xs)
    }

    private func add() {
        tags = Tags.merging(tags, with: [text])
        text = ""
    }

    private func chips(_ values: [String], @ViewBuilder chip: @escaping (String) -> some View) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: KWSpacing.xs) {
                ForEach(values, id: \.self, content: chip)
            }
        }
        .scrollIndicators(.hidden)
    }
}
