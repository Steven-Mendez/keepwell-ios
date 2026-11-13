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

    /// "America/Managua", or "America/Managua · From this iPhone" while none is saved yet. It is the
    /// row's second line rather than its trailing value: a zone name is long, and beside a title
    /// with a description the trailing value was squeezed to nothing.
    static func summary(saved: String?, device: TimeZone = .current) -> String {
        guard let saved else {
            let zone = SettingsTimeZonePicker.label(device.identifier)
            return String(localized: "\(zone) · From this iPhone", bundle: #bundle)
        }
        return SettingsTimeZonePicker.label(saved)
    }

    var body: some View {
        Button { isPicking = true } label: {
            KWSettingsRow(
                String(localized: "Time zone", bundle: #bundle),
                description: Self.summary(saved: settings.timeZone),
                icon: .globe,
                tint: KWSettingsTint.reminders,
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
            List {
                // The zone in use leads the list, marked, so it opens on it rather than on
                // "Africa/Abidjan" at the top of the alphabet. Searching shows matches only.
                if query.isEmpty {
                    Section {
                        row(selected)
                    } header: {
                        Text("Reminders and your assistant use it for today and for month ends.", bundle: #bundle)
                            .font(KWTextStyle.caption.font)
                            .foregroundStyle(KWColor.Text.muted)
                            .textCase(nil)
                    }
                }
                Section {
                    ForEach(zones, id: \.self, content: row)
                } header: {
                    if query.isEmpty {
                        Text("All time zones", bundle: #bundle)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(KWColor.Surface.bg)
            .searchable(text: $query, prompt: Text("Search time zone", bundle: #bundle))
            .navigationTitle(String(localized: "Time zone", bundle: #bundle))
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func row(_ zone: String) -> some View {
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
}
