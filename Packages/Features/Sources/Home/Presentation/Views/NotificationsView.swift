import DesignSystem
import Domain
import SharedPresentation
import SwiftUI

/// "Notifications": what needs attention (payments, renewals, budgets…) and the rules an assistant
/// proposed, grouped by day with the newest first. Each one can be read, unread or deleted, and
/// the same state follows the person to the web and to every iPhone.
public struct NotificationsView: View {
    private let viewModel: HomeViewModel
    private let onBack: () -> Void
    private let onOpen: (InboxItem.Destination) -> Void
    /// Fixed only in snapshots, where "what applies today" must not depend on when they run.
    private let now: Date
    /// The same eye as home: hiding amounts is about who's looking at the phone, on every screen.
    @AppStorage("home.hidesBalances") private var hidesBalances = false

    /// How long "Undo" stays on screen.
    private static let undoSeconds: Double = 5

    public init(
        viewModel: HomeViewModel,
        onBack: @escaping () -> Void,
        onOpen: @escaping (InboxItem.Destination) -> Void,
        now: Date = .now,
    ) {
        self.viewModel = viewModel
        self.onBack = onBack
        self.onOpen = onOpen
        self.now = now
    }

    public var body: some View {
        let inbox = viewModel.inboxSections(now: now, calendar: viewModel.calendar)
        let isEmpty = inbox.proposals.isEmpty && inbox.days.isEmpty
        return VStack(alignment: .leading, spacing: KWSpacing.md) {
            header(hasUnread: viewModel.inboxCount(now: now) > 0, hasRead: hasRead(inbox))
                .padding(.horizontal, KWLayout.gutter)
                .padding(.top, KWLayout.safeTop)
            if viewModel.state == .failed {
                Text("We couldn't load your notifications.", bundle: #bundle)
                    .foregroundStyle(KWColor.Text.muted)
                    .padding(.horizontal, KWLayout.gutter)
                Spacer(minLength: 0)
            } else if viewModel.overview != nil, isEmpty {
                KWEmptyState(
                    icon: .bell,
                    title: String(localized: "You're all caught up", bundle: #bundle),
                    message: String(localized: "Nothing needs your attention right now.", bundle: #bundle),
                )
                .padding(.vertical, KWSpacing.xl)
                .frame(maxWidth: .infinity)
                Spacer(minLength: 0)
            } else {
                list(inbox)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(KWColor.Surface.bg)
        .foregroundStyle(KWColor.Text.primary)
        .ignoresSafeArea(edges: .top)
        .overlay(alignment: .bottom) { undoToast }
        .toolbar(.hidden, for: .navigationBar)
        .task { await viewModel.load() }
    }

    private func hasRead(_ inbox: (proposals: [InboxItem], days: [InboxSection])) -> Bool {
        inbox.days.contains { $0.items.contains(where: \.isRead) }
    }

    // MARK: - Header

    private func header(hasUnread: Bool, hasRead: Bool) -> some View {
        KWNavigationHeader(String(localized: "Notifications", bundle: #bundle), style: .large, onBack: onBack)
            .padding(.trailing, 52)
            .overlay(alignment: .trailing) {
                Menu {
                    Button {
                        Task { await viewModel.markAllRead(now: now) }
                    } label: {
                        Label(String(localized: "Mark all as read", bundle: #bundle), systemImage: "checkmark.circle")
                    }
                    .disabled(!hasUnread)
                    Button(role: .destructive) {
                        Task { await viewModel.deleteRead(now: now) }
                    } label: {
                        Label(String(localized: "Delete read", bundle: #bundle), systemImage: "trash")
                    }
                    .disabled(!hasRead)
                } label: {
                    KWIconView(.more, size: 20)
                        .frame(width: 40, height: 40)
                        .background(KWColor.Surface.surface, in: Circle())
                        .contentShape(Circle())
                }
                .accessibilityLabel(String(localized: "More", bundle: #bundle))
                .disabled(!viewModel.canChangeNotifications)
            }
    }

    // MARK: - List

    private func list(_ inbox: (proposals: [InboxItem], days: [InboxSection])) -> some View {
        List {
            if !inbox.proposals.isEmpty {
                Section {
                    ForEach(inbox.proposals) { item in
                        proposalRow(item)
                    }
                } header: {
                    sectionTitle(String(localized: "Proposed by Claude", bundle: #bundle))
                }
            }
            ForEach(inbox.days) { section in
                Section {
                    ForEach(section.items) { item in
                        row(item)
                    }
                } header: {
                    sectionTitle(section.title)
                }
            }
            if let error = viewModel.actionError {
                Text(error).font(KWTextStyle.caption.font).foregroundStyle(KWColor.State.negative)
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
        .contentMargins(.bottom, KWSpacing.xxxl, for: .scrollContent)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(KWTextStyle.caption.font.weight(.semibold))
            .foregroundStyle(KWColor.Text.muted)
            .textCase(nil)
            .accessibilityAddTraits(.isHeader)
    }

    private func row(_ item: InboxItem) -> some View {
        Button {
            Task {
                await viewModel.open(item)
                if let destination = item.destination {
                    onOpen(destination)
                }
            }
        } label: {
            NotificationRow(item: item, hidesBalances: hidesBalances)
        }
        .buttonStyle(.plain)
        .listRowBackground(KWColor.Surface.surface)
        .listRowSeparatorTint(KWColor.Surface.border)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                Task { await viewModel.delete(item) }
            } label: {
                Label(String(localized: "Delete", bundle: #bundle), systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                Task { await viewModel.toggleRead(item) }
            } label: {
                if item.isRead {
                    Label(String(localized: "Mark as unread", bundle: #bundle), systemImage: "envelope.badge")
                } else {
                    Label(String(localized: "Mark as read", bundle: #bundle), systemImage: "envelope.open")
                }
            }
            .tint(KWColor.Brand.link)
        }
        .accessibilityAction(named: Text(item.isRead ? "Mark as unread" : "Mark as read", bundle: #bundle)) {
            Task { await viewModel.toggleRead(item) }
        }
        .accessibilityAction(named: Text("Delete", bundle: #bundle)) {
            Task { await viewModel.delete(item) }
        }
    }

    private func proposalRow(_ item: InboxItem) -> some View {
        HStack(spacing: KWSpacing.xs) {
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title).font(.kw(15, weight: item.isRead ? 500 : 700)).lineLimit(1)
                if let rule = item.proposal {
                    Text(viewModel.proposalSubtitle(rule, hidden: hidesBalances))
                        .font(KWTextStyle.captionSm.font)
                        .foregroundStyle(KWColor.Text.muted)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if viewModel.canResolveProposals, let rule = item.proposal {
                Button {
                    Task { await viewModel.discardProposal(rule) }
                } label: {
                    Text("Discard", bundle: #bundle)
                }
                .buttonStyle(.kw(.secondary, size: .mini))
                Button {
                    Task { await viewModel.confirmProposal(rule) }
                } label: {
                    Text("Confirm", bundle: #bundle)
                }
                .buttonStyle(.kw(.primary, size: .mini))
            }
        }
        .padding(.vertical, KWSpacing.xs)
        .listRowBackground(KWColor.Surface.surface)
        .listRowSeparatorTint(KWColor.Surface.border)
    }

    // MARK: - Undo

    @ViewBuilder
    private var undoToast: some View {
        if let offer = viewModel.undoOffer {
            KWToast(
                offer.ids.count == 1
                    ? String(localized: "Notification deleted", bundle: #bundle)
                    : String(localized: "\(offer.ids.count) notifications deleted", bundle: #bundle),
                actionTitle: String(localized: "Undo", bundle: #bundle),
            ) {
                Task { await viewModel.undo(offer) }
            }
            .padding(.horizontal, KWLayout.gutter)
            .padding(.bottom, KWSpacing.md)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .task(id: offer.id) {
                try? await Task.sleep(for: .seconds(Self.undoSeconds))
                guard !Task.isCancelled else { return }
                withAnimation { viewModel.clearUndoOffer() }
            }
        }
    }
}
