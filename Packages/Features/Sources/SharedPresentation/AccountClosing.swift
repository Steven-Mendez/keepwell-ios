import Core
import DesignSystem
import Domain
import Foundation
import Observation
import SwiftUI

/// Closing and reopening one account, shared by the bank account, cash and credit card screens.
@MainActor
@Observable
public final class AccountClosingModel {
    public let accountID: UUID
    /// What closing would do now; nil until loaded.
    public private(set) var plan: ClosingPlan?
    /// Where a balance left goes; the first possible one until the person picks another.
    public var destinationID: UUID?
    public private(set) var isSaving = false
    public private(set) var errorMessage: String?

    private let getPlan: any GetClosingPlanUseCase
    private let close: any CloseAccountUseCase
    private let reopen: any ReopenAccountUseCase

    public init(
        accountID: UUID,
        getPlan: any GetClosingPlanUseCase,
        close: any CloseAccountUseCase,
        reopen: any ReopenAccountUseCase,
    ) {
        self.accountID = accountID
        self.getPlan = getPlan
        self.close = close
        self.reopen = reopen
    }

    public func load() async {
        plan = try? await getPlan.execute(accountID: accountID)
        if let plan, !plan.destinations.contains(where: { $0.id == destinationID }) {
            destinationID = plan.destinations.first?.id
        }
    }

    /// With money left and nowhere to move it, the sheet asks to move or record it first.
    public var isBlocked: Bool {
        guard let plan else { return true }
        return !plan.balances.isEmpty && destinationID == nil
    }

    /// Returns whether the account is closed, so the sheet can go.
    public func closeAccount() async -> Bool {
        await perform { () async throws(DomainError) in
            try await close.execute(
                accountID: accountID,
                transferTo: plan?.balances.isEmpty == false ? destinationID : nil,
                description: String(localized: "Closing transfer", bundle: #bundle),
            )
        }
    }

    public func reopenAccount() async -> Bool {
        await perform { () async throws(DomainError) in
            try await reopen.execute(accountID: accountID)
        }
    }

    private func perform(_ action: () async throws(DomainError) -> Void) async -> Bool {
        isSaving = true
        defer { isSaving = false }
        do {
            try await action()
            errorMessage = nil
            await load()
            return true
        } catch {
            errorMessage = String(localized: "We couldn't close the account. Try again.", bundle: #bundle)
            return false
        }
    }
}

/// The texts every screen with accounts reads about closing.
public enum AccountClosingText {
    /// The "Close account" row, before "Delete account".
    public static var closeAccount: String {
        String(localized: "Close account", bundle: #bundle)
    }

    /// Next to a closed account in a picker or filter.
    public static var closed: String {
        String(localized: "Closed", bundle: #bundle)
    }

    /// "Closed on 12 Nov 2026".
    public static func closedOn(_ date: Date) -> String {
        let day = date.formatted(date: .abbreviated, time: .omitted)
        return String(localized: "Closed on \(day)", bundle: #bundle)
    }

    /// "Closed (2)", the folded section at the foot of Accounts.
    public static func closedSection(_ count: Int) -> String {
        String(localized: "Closed (\(count))", bundle: #bundle)
    }

    /// Added to the delete confirmation of an open account with movements.
    public static var closeInsteadHint: String {
        String(localized: "To keep its history, close it instead.", bundle: #bundle)
    }

    public static var closeInstead: String {
        String(localized: "Close instead", bundle: #bundle)
    }

    /// What a save says when the movement would change a closed account's balance.
    public static var accountClosedError: String {
        String(localized: "This account is closed. Reopen it first.", bundle: #bundle)
    }
}

/// "Close …?": with a zero balance it only asks; with money left it shows the balance per currency
/// and the open accounts that can receive it, or says to move it first.
public struct CloseAccountSheet: View {
    @Bindable private var model: AccountClosingModel
    private let accountName: String
    private let onClosed: () -> Void
    private let onDismiss: () -> Void
    private let formatter = CurrencyFormatter()

    public init(model: AccountClosingModel, accountName: String, onClosed: @escaping () -> Void, onDismiss: @escaping () -> Void) {
        self.model = model
        self.accountName = accountName
        self.onClosed = onClosed
        self.onDismiss = onDismiss
    }

    public var body: some View {
        KWScreen(top: KWSpacing.xl, bottom: KWSpacing.xl) {
            VStack(alignment: .leading, spacing: KWSpacing.md) {
                KWFlowHeader(.close, action: onDismiss)
                Text("Close \(accountName)?", bundle: #bundle).kwTextStyle(.titleSm).accessibilityAddTraits(.isHeader)
                Text(
                    "It disappears from your lists and pickers. Its movements stay in your summaries and net worth. You can reopen it.",
                    bundle: #bundle,
                )
                .font(KWTextStyle.body.font)
                .foregroundStyle(KWColor.Text.muted)
                if let plan = model.plan {
                    consequences(plan)
                    balance(plan)
                }
                if let error = model.errorMessage {
                    Text(error)
                        .font(KWTextStyle.caption.font)
                        .foregroundStyle(KWColor.State.negative)
                }
                Spacer(minLength: 0)
                if !model.isBlocked {
                    Button {
                        Task {
                            if await model.closeAccount() {
                                onClosed()
                            }
                        }
                    } label: {
                        if model.plan?.balances.isEmpty == false {
                            Text("Move and close", bundle: #bundle)
                        } else {
                            Text("Close account", bundle: #bundle)
                        }
                    }
                    .buttonStyle(.kw())
                    .disabled(model.isSaving)
                }
            }
        }
        .task { await model.load() }
    }

    @ViewBuilder
    private func consequences(_ plan: ClosingPlan) -> some View {
        if !plan.rulesToPause.isEmpty {
            Text("Recurring rules paused: \(plan.rulesToPause.count)", bundle: #bundle)
                .font(KWTextStyle.caption.font)
                .foregroundStyle(KWColor.Text.muted)
        }
        if !plan.draftsToDelete.isEmpty {
            Text("Drafts deleted: \(plan.draftsToDelete.count)", bundle: #bundle)
                .font(KWTextStyle.caption.font)
                .foregroundStyle(KWColor.Text.muted)
        }
    }

    @ViewBuilder
    private func balance(_ plan: ClosingPlan) -> some View {
        if !plan.balances.isEmpty {
            Text(formatter.joined(plan.balances))
                .font(KWTextStyle.amountSm.font)
            if plan.destinations.isEmpty {
                Text("Move or record the balance first", bundle: #bundle)
                    .font(KWTextStyle.body.font)
                    .foregroundStyle(KWColor.State.pending)
            } else {
                Text("Move the balance to", bundle: #bundle)
                    .font(KWTextStyle.caption.font)
                    .foregroundStyle(KWColor.Text.muted)
                KWGroupedCard(verticalPadding: KWSpacing.xxs) {
                    ForEach(plan.destinations) { account in
                        Button {
                            model.destinationID = account.id
                        } label: {
                            HStack {
                                Text(CardDisplay.name(of: account))
                                Spacer()
                                if model.destinationID == account.id {
                                    KWIconView(.check, size: 18)
                                }
                            }
                            .padding(.vertical, KWSpacing.sm)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(model.destinationID == account.id ? .isSelected : [])
                    }
                }
            }
        }
    }
}

/// The head of a closed account's screen: when it closed, a warning if money came back, and "Reopen".
public struct ClosedAccountBanner: View {
    private let model: AccountClosingModel
    private let closedAt: Date
    private let onReopened: () -> Void

    public init(model: AccountClosingModel, closedAt: Date, onReopened: @escaping () -> Void) {
        self.model = model
        self.closedAt = closedAt
        self.onReopened = onReopened
    }

    public var body: some View {
        KWGroupedCard {
            HStack(spacing: KWSpacing.md) {
                VStack(alignment: .leading, spacing: KWSpacing.xxs) {
                    Text(AccountClosingText.closedOn(closedAt))
                        .font(KWTextStyle.body.font)
                    if model.plan?.balances.isEmpty == false {
                        Text("Balance isn't zero", bundle: #bundle)
                            .font(KWTextStyle.caption.font)
                            .foregroundStyle(KWColor.State.pending)
                    }
                }
                Spacer(minLength: 0)
                Button {
                    Task {
                        if await model.reopenAccount() {
                            onReopened()
                        }
                    }
                } label: {
                    Text("Reopen", bundle: #bundle)
                }
                .buttonStyle(.kw(.primary, size: .small))
                .disabled(model.isSaving)
            }
            .padding(.vertical, KWSpacing.sm)
        }
        .task { await model.load() }
    }
}

extension View {
    /// Presents "Close …?" for `model` (nothing without one); `onChanged` reloads the screen after.
    public func accountClosingSheet(
        _ model: AccountClosingModel?,
        accountName: String,
        isPresented: Binding<Bool>,
        onChanged: @escaping () -> Void,
    ) -> some View {
        sheet(isPresented: isPresented) {
            if let model {
                CloseAccountSheet(
                    model: model,
                    accountName: accountName,
                    onClosed: {
                        isPresented.wrappedValue = false
                        onChanged()
                    },
                    onDismiss: { isPresented.wrappedValue = false },
                )
                .presentationDetents([.large])
                .presentationBackground(KWColor.Surface.bg)
            }
        }
    }
}

/// The foot of an account's screen: "Close account" (while open) before "Delete account".
public struct AccountLifecycleRows: View {
    private let canClose: Bool
    private let deleteTitle: String
    private let onClose: () -> Void
    private let onDelete: () -> Void

    /// `deleteTitle` is the screen's own "Delete account".
    public init(canClose: Bool, deleteTitle: String, onClose: @escaping () -> Void, onDelete: @escaping () -> Void) {
        self.canClose = canClose
        self.deleteTitle = deleteTitle
        self.onClose = onClose
        self.onDelete = onDelete
    }

    public var body: some View {
        KWGroupedCard(verticalPadding: KWSpacing.xxs) {
            if canClose {
                CardManageRow(AccountClosingText.closeAccount, icon: .lock, action: onClose)
            }
            CardManageRow(deleteTitle, icon: .trash, isDestructive: true, action: onDelete)
        }
    }
}
