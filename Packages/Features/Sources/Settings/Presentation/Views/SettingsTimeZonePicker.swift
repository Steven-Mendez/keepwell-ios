import DesignSystem
import Domain
import SwiftUI

/// The home time zone (`Settings.timeZone`): what Keepwell's server reads "today" and month ends in,
/// for reminders and assistants. Set from the device when missing; changed only here. The app's
/// screens keep the iPhone's own calendar.
struct TimeZoneRow: View {
    @Bindable var viewModel: SettingsViewModel
    let settings: Settings
    @State private var isPicking = false

    private var current: String {
        settings.timeZone ?? TimeZone.current.identifier
    }

    var body: some View {
        Button { isPicking = true } label: {
            KWSettingsRow(
                String(localized: "Time zone", bundle: #bundle),
                description: String(localized: "Reminders and your assistant use it for today and for month ends.", bundle: #bundle),
                icon: .globe,
                tint: KWSettingsTint.reminders,
                value: SettingsTimeZonePicker.label(current),
                accessory: .chevron,
            )
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $isPicking) {
            SettingsTimeZonePicker(selected: current) { zone in
                isPicking = false
                Task { await viewModel.setTimeZone(zone) }
            }
            .presentationDetents([.large])
            .presentationBackground(KWColor.Surface.bg)
        }
    }
}

/// Every zone the iPhone knows, searchable by name.
struct SettingsTimeZonePicker: View {
    let selected: String
    let onPick: (String) -> Void
    @State private var query = ""

    /// "America/Argentina/Buenos_Aires" reads "America/Argentina/Buenos Aires".
    static func label(_ identifier: String) -> String {
        identifier.replacingOccurrences(of: "_", with: " ")
    }

    private var zones: [String] {
        let known = Set(TimeZone.knownTimeZoneIdentifiers).union([selected])
        return known.filter { query.isEmpty || Self.label($0).localizedCaseInsensitiveContains(query) }.sorted()
    }

    var body: some View {
        NavigationStack {
            List(zones, id: \.self) { zone in
                Button { onPick(zone) } label: {
                    HStack {
                        Text(Self.label(zone)).font(KWTextStyle.body.font)
                        Spacer()
                        if zone == selected {
                            KWIconView(.check, size: 16)
                                .foregroundStyle(KWColor.Brand.linkHover)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(zone == selected ? .isSelected : [])
                .listRowBackground(KWColor.Surface.surface)
            }
            .scrollContentBackground(.hidden)
            .background(KWColor.Surface.bg)
            .searchable(text: $query, prompt: Text("Search time zone", bundle: #bundle))
            .navigationTitle(String(localized: "Time zone", bundle: #bundle))
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
