import CloudAccountDomain
import DesignSystem
import SwiftUI

/// Assistants connected through MCP: each with what it can do and a Disconnect, the guide to
/// connect Claude, and "Disconnect assistants" for all of them at once.
struct ConnectedAssistantsSection: View {
    let viewModel: CloudAccountViewModel
    @State private var isConfirmingDisconnectAll = false

    var body: some View {
        VStack(alignment: .leading, spacing: KWSpacing.xs) {
            KWSectionHeader(String(localized: "Connected assistants", bundle: #bundle)).padding(.leading, KWSpacing.xxs)
            card
            Text(
                "Assistants like Claude can read your data and record movements you then confirm here.",
                bundle: #bundle,
            )
            .font(KWTextStyle.captionSm.font.weight(.regular))
            .foregroundStyle(KWColor.Text.muted)
            .padding(.horizontal, KWSpacing.xxs)
        }
        .task { await viewModel.loadAssistants() }
        .confirmationDialog(
            String(localized: "Disconnect every assistant?", bundle: #bundle),
            isPresented: $isConfirmingDisconnectAll,
            titleVisibility: .visible,
        ) {
            Button(role: .destructive) {
                Task { await viewModel.disconnectAssistants() }
            } label: {
                Text("Disconnect all", bundle: #bundle)
            }
        } message: {
            Text("They lose access right away and would have to be connected again.", bundle: #bundle)
        }
    }

    private var card: some View {
        KWGroupedCard {
            assistantRows
            if let guide = viewModel.connectGuideURL {
                guideRow(guide)
            }
            disconnectAllRow
        }
    }

    @ViewBuilder
    private var assistantRows: some View {
        if let assistants = viewModel.assistants {
            if assistants.isEmpty {
                KWSettingsRow(
                    String(localized: "None connected", bundle: #bundle),
                    icon: .sparkles,
                    tint: KWSettingsTint.assistants,
                )
            }
            ForEach(assistants) { assistant in
                KWSettingsRow(
                    assistant.name ?? assistant.id,
                    description: Self.accessText(assistant.access),
                    icon: .sparkles,
                    tint: KWSettingsTint.assistants,
                ) {
                    Button {
                        Task { await viewModel.disconnectAssistant(assistant.id) }
                    } label: {
                        Text("Disconnect", bundle: #bundle)
                            .font(.kw(13, weight: 600, relativeTo: .footnote))
                            .foregroundStyle(KWColor.State.negative)
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isWorking)
                }
            }
        }
    }

    private func guideRow(_ guide: URL) -> some View {
        Link(destination: guide) {
            KWSettingsRow(
                String(localized: "How to connect Claude", bundle: #bundle),
                description: String(
                    localized: "Step by step, on the web, desktop, phone and Claude Code.",
                    bundle: #bundle,
                ),
                icon: .list,
                tint: KWSettingsTint.about,
                accessory: .chevron,
            )
        }
        .buttonStyle(.plain)
    }

    private var disconnectAllRow: some View {
        Button { isConfirmingDisconnectAll = true } label: {
            KWSettingsRow(
                viewModel.assistantsDisconnected
                    ? String(localized: "Assistants disconnected", bundle: #bundle)
                    : String(localized: "Disconnect assistants", bundle: #bundle),
                description: String(
                    localized: "Claude and other assistants lose access to your account at once.",
                    bundle: #bundle,
                ),
                icon: .close,
                isDestructive: true,
            )
        }
        .buttonStyle(.plain)
        .disabled(viewModel.assistantsDisconnected || viewModel.isWorking)
    }

    private static func accessText(_ access: ConnectedAssistant.Access) -> String {
        switch access {
        case .fullControl: String(localized: "Full control", bundle: #bundle)
        case .readAndRecord: String(localized: "Can read and record", bundle: #bundle)
        case .read: String(localized: "Can read", bundle: #bundle)
        }
    }
}
