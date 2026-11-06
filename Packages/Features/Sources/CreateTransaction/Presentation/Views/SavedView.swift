import CreateTransactionDomain
import DesignSystem
import Domain
import SwiftUI
import UIKit

/// The receipt: a ticket with what was saved, where it moved, the rate and the new balance, with
/// two round actions at its foot, as a bank's receipt: save it to Photos or share it as an image.
public struct SavedView: View {
    private let viewModel: CreateTransactionViewModel
    private let onClose: () -> Void
    /// Rendered once per receipt, since the share sheet needs the image up front.
    @State private var image: RenderedReceipt?
    @Environment(\.openURL) private var openURL

    public init(viewModel: CreateTransactionViewModel, onClose: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onClose = onClose
    }

    public var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                if let saved = viewModel.saved {
                    ReceiptTicket(viewModel: viewModel, saved: saved) {
                        actions(saved)
                    }
                    .padding(.top, 36)
                }
            }
            .scrollIndicators(.hidden)
            .contentMargins(.horizontal, KWLayout.gutter, for: .scrollContent)
            .contentMargins(.top, KWLayout.safeTop, for: .scrollContent)
            HStack(spacing: 10) {
                Button { Task { await viewModel.startOver() } } label: { Text("Log another", bundle: #bundle) }
                    .buttonStyle(.kw(.surface, size: .regular))
                Button(action: onClose) { Text("Done", bundle: #bundle) }
                    .buttonStyle(.kw(.primary, size: .regular))
            }
            .padding(.horizontal, KWLayout.gutter)
            .padding(.top, KWSpacing.sm)
            .padding(.bottom, 34)
        }
        .ignoresSafeArea(.container, edges: [.top, .bottom])
        .background(KWColor.Surface.bg)
        .foregroundStyle(KWColor.Text.primary)
        .task(id: viewModel.saved?.transaction.id) { render() }
        .sensoryFeedback(.success, trigger: viewModel.receiptImageStatus == .saved)
        .alert(
            Text("Allow access to Photos", bundle: #bundle),
            isPresented: messageBinding(for: .denied),
        ) {
            Button { openSettings() } label: { Text("Open Settings", bundle: #bundle) }
            Button(role: .cancel) {} label: { Text("Not now", bundle: #bundle) }
        } message: {
            Text("Keepwell needs permission to add photos to save your receipt. You can turn it on in Settings.", bundle: #bundle)
        }
        .alert(
            Text("We couldn't save the image", bundle: #bundle),
            isPresented: messageBinding(for: .failed),
        ) {
            Button(role: .cancel) {} label: { Text("OK", bundle: #bundle) }
        } message: {
            Text("Try again, or share the receipt instead.", bundle: #bundle)
        }
    }

    // MARK: Actions

    private func actions(_ saved: SavedTransaction) -> some View {
        VStack(spacing: KWSpacing.md) {
            KWDivider()
            HStack(alignment: .top, spacing: KWSpacing.xl) {
                if viewModel.canSaveReceiptImage {
                    Button { Task { await viewModel.saveReceiptImage(image?.receipt.png) } } label: { saveLabel }
                        .buttonStyle(.plain)
                        .disabled(viewModel.receiptImageStatus == .saving || viewModel.receiptImageStatus == .saved)
                }
                shareLink(saved)
            }
        }
        .padding(.bottom, KWSpacing.md)
    }

    @ViewBuilder
    private var saveLabel: some View {
        switch viewModel.receiptImageStatus {
        case .saving:
            RoundAction(title: String(localized: "Save image", bundle: #bundle)) { ProgressView().tint(KWColor.Brand.link) }
        case .saved:
            RoundAction(title: String(localized: "Saved to Photos", bundle: #bundle), tint: KWColor.State.positive) {
                KWIconView(.check, size: 22)
            }
        case .idle, .denied, .failed:
            RoundAction(title: String(localized: "Save image", bundle: #bundle)) { KWIconView(.download, size: 22) }
        }
    }

    @ViewBuilder
    private func shareLink(_ saved: SavedTransaction) -> some View {
        let label = RoundAction(title: String(localized: "Share", bundle: #bundle)) { KWIconView(.share, size: 22) }
        if let image {
            ShareLink(
                item: image.receipt,
                preview: SharePreview(String(localized: "Share receipt", bundle: #bundle), image: image.preview),
            ) { label }
                .buttonStyle(.plain)
        } else {
            // Rendering failed: the text receipt still goes out.
            ShareLink(item: viewModel.receiptText(saved)) { label }
                .buttonStyle(.plain)
        }
    }

    // MARK: Private

    private func render() {
        guard let saved = viewModel.saved,
              let uiImage = ReceiptImageRenderer.image(of: viewModel, saved: saved),
              let png = uiImage.pngData()
        else {
            image = nil
            return
        }
        image = RenderedReceipt(
            receipt: ReceiptImage(
                png: png,
                text: viewModel.receiptText(saved),
                fileName: "Keepwell \(viewModel.reference(saved)).png",
            ),
            preview: Image(uiImage: uiImage),
        )
    }

    private func messageBinding(for status: CreateTransactionViewModel.ReceiptImageStatus) -> Binding<Bool> {
        Binding(
            get: { viewModel.receiptImageStatus == status },
            set: {
                if !$0 {
                    viewModel.dismissReceiptImageMessage()
                }
            },
        )
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            openURL(url)
        }
    }
}

private struct RenderedReceipt {
    let receipt: ReceiptImage
    let preview: Image
}

/// A tinted circle with its caption underneath, as the receipt actions of banking apps.
private struct RoundAction<Icon: View>: View {
    let title: String
    var tint: Color = KWColor.Brand.link
    @ViewBuilder let icon: Icon

    var body: some View {
        VStack(spacing: KWSpacing.xs) {
            icon
                .foregroundStyle(tint)
                .frame(width: 52, height: 52)
                .background(tint.opacity(0.14), in: Circle())
            Text(title)
                .font(.kw(13, weight: 600, relativeTo: .caption))
                .foregroundStyle(KWColor.Text.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(minWidth: 88)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
    }
}
