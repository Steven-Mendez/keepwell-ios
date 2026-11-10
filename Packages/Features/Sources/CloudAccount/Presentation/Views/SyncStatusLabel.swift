import CloudAccountDomain
import DesignSystem
import SwiftUI

/// Where sync stands, in one short line.
struct SyncStatus: Equatable {
    enum Tone {
        case good
        case busy
        case attention
        case off
    }

    let text: String
    let tone: Tone

    @MainActor
    init(user: CloudAccountUser, sync: SyncCoordinator?) {
        // The same six states keepwell-web's header shows.
        guard user.canSync else {
            self.init(String(localized: "Sync off", bundle: #bundle), .off)
            return
        }
        switch sync?.state {
        case .syncing:
            self.init(String(localized: "Syncing", bundle: #bundle), .busy)
        case .needsChoice:
            self.init(String(localized: "Sync paused", bundle: #bundle), .attention)
        case .offline:
            self.init(String(localized: "Offline", bundle: #bundle), .attention)
        case .failed:
            self.init(String(localized: "Couldn't sync", bundle: #bundle), .attention)
        case .needsPlan, .signedOut:
            self.init(String(localized: "Sync off", bundle: #bundle), .off)
        default:
            self.init(String(localized: "Synced", bundle: #bundle), .good)
        }
    }

    private init(_ text: String, _ tone: Tone) {
        self.text = text
        self.tone = tone
    }
}

struct SyncStatusLabel: View {
    let status: SyncStatus

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(status.text)
                .font(KWTextStyle.captionSm.font)
                .foregroundStyle(KWColor.Text.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
    }

    private var color: Color {
        switch status.tone {
        case .good: KWColor.State.positive
        case .busy: KWColor.Brand.link
        case .attention: KWColor.State.pending
        case .off: KWColor.Text.faint
        }
    }
}
