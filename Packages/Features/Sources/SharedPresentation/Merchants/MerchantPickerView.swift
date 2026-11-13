import DesignSystem
import Domain
import SwiftUI

/// The sheet behind "Business" and "Via": a search field over the person's merchants, the brand
/// table and Brandfetch's search, and "Add “…”" for a name typed by hand.
public struct MerchantPickerView: View {
    @Bindable private var viewModel: MerchantPickerViewModel
    @FocusState private var isFocused: Bool
    @Environment(\.dismiss) private var dismiss

    public init(viewModel: MerchantPickerViewModel) {
        self.viewModel = viewModel
    }

    private var title: String {
        viewModel.role == .via
            ? String(localized: "Via", bundle: #bundle)
            : String(localized: "Business", bundle: #bundle)
    }

    public var body: some View {
        NavigationStack {
            List {
                Section { searchField }
                Section {
                    ForEach(viewModel.options) { option in
                        Button {
                            viewModel.pick(option)
                            dismiss()
                        } label: {
                            row(option)
                        }
                        .buttonStyle(.plain)
                    }
                    if viewModel.isSearching {
                        ProgressView().frame(maxWidth: .infinity)
                    }
                } footer: {
                    if viewModel.options.isEmpty {
                        Text("Type a name to add a business.", bundle: #bundle)
                    }
                }
                if viewModel.current != nil {
                    Section { removeButton }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text("Cancel", bundle: #bundle) }
                }
            }
            .onAppear { isFocused = true }
        }
    }

    private var searchField: some View {
        TextField(
            String(localized: "Search or add a business", bundle: #bundle),
            text: $viewModel.query,
            prompt: Text(viewModel.role == .via ? "Uber Eats, App Store…" : "Search or add a business", bundle: #bundle),
        )
        .focused($isFocused)
        .textInputAutocapitalization(.words)
        .autocorrectionDisabled()
        .submitLabel(.done)
    }

    private var removeButton: some View {
        Button(role: .destructive) {
            viewModel.clear()
            dismiss()
        } label: {
            Text("Remove", bundle: #bundle)
        }
    }

    private func row(_ option: MerchantOption) -> some View {
        HStack(spacing: KWSpacing.sm) {
            if let logo = option.logo {
                BrandMark(logo, tint: KWColor.Text.secondary, diameter: 28)
            } else {
                Text(verbatim: option.group == .new ? "+" : String(option.label.prefix(1)).uppercased())
                    .font(.kw(13, weight: 700))
                    .foregroundStyle(KWColor.Text.secondary)
                    .frame(width: 28, height: 28)
                    .background(KWColor.Surface.surface2, in: Circle())
                    .accessibilityHidden(true)
            }
            Text(option.group == .new ? String(localized: "Add “\(option.label)”", bundle: #bundle) : option.label)
                .font(.kw(15, weight: 500))
                .foregroundStyle(KWColor.Text.primary)
                .lineLimit(1)
            Spacer(minLength: 0)
            if let detail = option.detail {
                Text(verbatim: detail)
                    .font(.kw(12, weight: 400))
                    .foregroundStyle(KWColor.Text.muted)
                    .lineLimit(1)
            }
        }
        .contentShape(Rectangle())
    }
}
