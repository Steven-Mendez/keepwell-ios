import CoreTransferable
import CreateTransactionDomain
import DesignSystem
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// The receipt as a picture: the ticket on the brand background under the wordmark, without the
/// screen's buttons, so what lands in Photos or a chat reads on its own.
struct ReceiptImageView: View {
    let viewModel: CreateTransactionViewModel
    let saved: SavedTransaction

    var body: some View {
        VStack(spacing: 0) {
            KWWordmark(height: 26)
                .padding(.bottom, 52)
            ReceiptTicket(viewModel: viewModel, saved: saved, backdrop: KWColor.Brand.b500) {
                Color.clear.frame(height: KWSpacing.sm)
            }
        }
        .padding(.horizontal, KWSpacing.lg)
        .padding(.top, 36)
        .padding(.bottom, 40)
        // `ImageRenderer` sizes the canvas a few points taller than the content and centers it,
        // so the gradient stretches to the whole canvas instead of leaving transparent bands.
        .frame(width: ReceiptImageRenderer.width)
        .frame(maxHeight: .infinity)
        .background(KWColor.Brand.gradient)
        .foregroundStyle(KWColor.Text.primary)
        .environment(\.colorScheme, .dark)
    }
}

/// Draws `ReceiptImageView` at 3× so the saved receipt stays sharp when zoomed in Photos.
@MainActor
enum ReceiptImageRenderer {
    static let width: CGFloat = 390
    static let scale: CGFloat = 3

    static func image(of viewModel: CreateTransactionViewModel, saved: SavedTransaction) -> UIImage? {
        let renderer = ImageRenderer(content: ReceiptImageView(viewModel: viewModel, saved: saved))
        renderer.scale = scale
        renderer.proposedSize = ProposedViewSize(width: width, height: nil)
        return renderer.uiImage
    }
}

/// What "Share" hands over: the PNG first, and the plain-text receipt for targets that only take
/// text (and as the image's description for VoiceOver users who receive it).
struct ReceiptImage: Transferable, Sendable {
    let png: Data
    let text: String
    let fileName: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { $0.png }
            .suggestedFileName { $0.fileName }
        ProxyRepresentation(exporting: \.text)
    }
}
