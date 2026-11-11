import DesignSystem
import SwiftUI

/// Every ISO currency, searchable by code or name, for Settings. "None" is offered for the second
/// currency, which goes back to a single currency.
struct SettingsCurrencyPicker: View {
    let title: String
    let selected: String?
    let excluding: String?
    let allowsNone: Bool
    let name: (String) -> String
    /// `nil` is "None".
    let onPick: (String?) -> Void
    @State private var query = ""

    private var codes: [String] {
        Locale.commonISOCurrencyCodes.filter { $0 != excluding && (query.isEmpty || matches($0)) }
    }

    private func matches(_ code: String) -> Bool {
        code.localizedCaseInsensitiveContains(query) || name(code).localizedCaseInsensitiveContains(query)
    }

    var body: some View {
        NavigationStack {
            List {
                if allowsNone, query.isEmpty {
                    row(String(localized: "None", bundle: #bundle), code: nil)
                }
                ForEach(codes, id: \.self) { code in
                    row(name(code), code: code)
                }
            }
            .scrollContentBackground(.hidden)
            .background(KWColor.Surface.bg)
            .searchable(text: $query, prompt: Text("Search currency", bundle: #bundle))
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func row(_ label: String, code: String?) -> some View {
        Button { onPick(code) } label: {
            HStack {
                Text(label).font(KWTextStyle.body.font)
                Spacer()
                if code == selected {
                    KWIconView(.check, size: 16)
                        .foregroundStyle(KWColor.Brand.linkHover)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(code == selected ? .isSelected : [])
        .listRowBackground(KWColor.Surface.surface)
    }
}
