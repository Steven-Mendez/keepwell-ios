import DesignSystem
import SwiftUI

/// The split's public link: who it is for, its QR code, "Share link" and "Stop sharing"; without an
/// account that syncs, a summary to share as text.
struct SplitShareSection: View {
    @Bindable var viewModel: SplitDetailViewModel

    var body: some View {
        KWGroupedCard {
            sharingContent
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 12)
        }
    }

    private var sharingContent: some View {
        VStack(alignment: .leading, spacing: KWSpacing.sm) {
            Text("Public link", bundle: #bundle).font(KWTextStyle.label.font)
            if !viewModel.canShareLink {
                Text("A link that stays up to date needs a Keepwell account. Share a summary instead.", bundle: #bundle)
                    .font(KWTextStyle.caption.font)
                    .foregroundStyle(KWColor.Text.muted)
                ShareLink(item: viewModel.summary) {
                    Text("Share summary", bundle: #bundle)
                }
                .buttonStyle(.kw(.surface, size: .small))
            } else if let url = viewModel.shareURL {
                shared(url)
            } else {
                Text("Send a link so each person sees how much to pay, without an account.", bundle: #bundle)
                    .font(KWTextStyle.caption.font)
                    .foregroundStyle(KWColor.Text.muted)
                Button { Task { await viewModel.share() } } label: {
                    Text("Create link", bundle: #bundle)
                }
                .buttonStyle(.kw(size: .small))
                .disabled(viewModel.isSaving || viewModel.debts.isEmpty)
            }
        }
    }

    /// The live link: who it is for, its QR code to scan at the table, "Share link" and "Stop sharing".
    @ViewBuilder
    private func shared(_ url: URL) -> some View {
        Text("Anyone with the link sees what each person owes and who already paid. Only you can change it.", bundle: #bundle)
            .font(KWTextStyle.caption.font)
            .foregroundStyle(KWColor.Text.muted)
        linkForMenu
        if let code = QRCode.image(for: url) {
            Image(uiImage: code)
                .interpolation(.none)
                .resizable()
                .frame(width: 168, height: 168)
                .padding(KWSpacing.xs)
                .background(.white, in: RoundedRectangle(cornerRadius: 12))
                .frame(maxWidth: .infinity)
                .accessibilityLabel(Text("QR code of the link", bundle: #bundle))
        }
        HStack {
            ShareLink(item: url) {
                Text("Share link", bundle: #bundle)
            }
            .buttonStyle(.kw(size: .small))
            Button { Task { await viewModel.stopSharing() } } label: {
                Text("Stop sharing", bundle: #bundle)
            }
            .buttonStyle(.kw(.surface, size: .small))
        }
    }

    /// "Link for Everyone ▾": the link can open the page on one person's share.
    private var linkForMenu: some View {
        Menu {
            Picker(selection: $viewModel.linkFor) {
                Text("Everyone", bundle: #bundle).tag(String?.none)
                ForEach(viewModel.people, id: \.self) { person in
                    Text(person).tag(String?.some(person))
                }
            } label: {
                EmptyView()
            }
        } label: {
            HStack(spacing: KWSpacing.xxs) {
                Text("Link for", bundle: #bundle).foregroundStyle(KWColor.Text.muted)
                Text(viewModel.linkFor ?? String(localized: "Everyone", bundle: #bundle))
                    .foregroundStyle(KWColor.Brand.link)
                KWIconView(.chevronRight, size: 12).rotationEffect(.degrees(90)).foregroundStyle(KWColor.Brand.link)
            }
            .font(KWTextStyle.label.font)
        }
    }
}
