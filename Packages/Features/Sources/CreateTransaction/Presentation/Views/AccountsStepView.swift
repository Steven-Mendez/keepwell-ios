import DesignSystem
import Domain
import SharedPresentation
import SwiftUI

/// Transfers, withdrawals and card payments start here: the account the money leaves, as a card
/// that opens the other options, then the accounts that can receive it, one to pick.
public struct AccountsStepView: View {
    private let viewModel: CreateTransactionViewModel
    private let onBack: () -> Void
    @State private var isPickingSource = false

    public init(viewModel: CreateTransactionViewModel, onBack: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onBack = onBack
    }

    public var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: KWSpacing.sm) {
                    KWFlowHeader(.close, progress: viewModel.progress(of: .accounts), action: onBack)
                    Text(viewModel.typeTitle)
                        .kwTextStyle(.titleSm)
                        .padding(.top, KWSpacing.xxs)
                        .accessibilityAddTraits(.isHeader)
                    sectionTitle(viewModel.sourceQuestion)
                    source
                    sectionTitle(viewModel.destinationQuestion).padding(.top, KWSpacing.xs)
                    destinations
                }
                .padding(.horizontal, KWLayout.gutter)
                .padding(.top, KWLayout.safeTop)
                .padding(.bottom, KWSpacing.md)
            }
            .scrollIndicators(.hidden)
            Button { viewModel.continueFromAccounts() } label: { Text("Continue", bundle: #bundle) }
                .buttonStyle(.kw())
                .disabled(!viewModel.canContinueFromAccounts)
                .padding(.horizontal, KWLayout.gutter)
                .padding(.top, KWSpacing.sm)
                .padding(.bottom, 34)
        }
        .ignoresSafeArea(.container, edges: [.top, .bottom])
        .background(KWColor.Surface.bg)
        .foregroundStyle(KWColor.Text.primary)
        .sheet(isPresented: $isPickingSource) {
            SourcePicker(viewModel: viewModel) { isPickingSource = false }
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.kw(13, weight: 600, relativeTo: .footnote))
            .foregroundStyle(KWColor.Text.muted)
            .padding(.top, KWSpacing.xxs)
    }

    @ViewBuilder
    private var source: some View {
        if let account = viewModel.sourceAccount {
            Button { isPickingSource = true } label: {
                AccountRowCard(
                    thumbnail: viewModel.thumbnail(of: account),
                    title: CardDisplay.name(of: account),
                    detail: viewModel.balanceLabel(of: account),
                ) {
                    if viewModel.sourceOptions.count > 1 {
                        KWIconView(.chevronRight, size: 18).foregroundStyle(KWColor.Text.muted)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(viewModel.sourceOptions.count < 2)
            .accessibilityHint(Text("Choose another account", bundle: #bundle))
        }
    }

    @ViewBuilder
    private var destinations: some View {
        if viewModel.destinationOptions.isEmpty {
            Text("No account can receive it from this one.", bundle: #bundle)
                .font(KWTextStyle.label.font.weight(.regular))
                .foregroundStyle(KWColor.Text.muted)
        }
        ForEach(viewModel.destinationOptions) { account in
            let isSelected = account.id == viewModel.destinationAccountID
            Button { viewModel.selectDestination(account.id) } label: {
                AccountRowCard(
                    thumbnail: viewModel.thumbnail(of: account),
                    title: CardDisplay.name(of: account),
                    detail: viewModel.balanceLabel(of: account),
                ) { RadioIndicator(isSelected: isSelected) }
                    .overlay {
                        if isSelected {
                            RoundedRectangle(cornerRadius: KWRadius.surface, style: .continuous)
                                .strokeBorder(KWColor.State.positive.opacity(0.6), lineWidth: 1.5)
                        }
                    }
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        }
    }
}

/// The other accounts money can leave from.
private struct SourcePicker: View {
    let viewModel: CreateTransactionViewModel
    let onDone: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KWSpacing.sm) {
                Text(viewModel.sourceQuestion).kwTextStyle(.titleSm).accessibilityAddTraits(.isHeader)
                ForEach(viewModel.sourceOptions) { account in
                    let isSelected = account.id == viewModel.sourceAccount?.id
                    Button {
                        viewModel.selectSourceAccount(account.id)
                        onDone()
                    } label: {
                        AccountRowCard(
                            thumbnail: viewModel.thumbnail(of: account),
                            title: CardDisplay.name(of: account),
                            detail: viewModel.balanceLabel(of: account),
                        ) { RadioIndicator(isSelected: isSelected) }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(KWLayout.gutter)
            .padding(.top, KWSpacing.xs)
        }
        .foregroundStyle(KWColor.Text.primary)
        .presentationDetents([.medium, .large])
        .presentationBackground(KWColor.Surface.bg)
    }
}
