import CloudAccountDomain
import Foundation
import StoreKit

/// The coffee through StoreKit 2. Only transactions StoreKit verified on the device are passed on,
/// and the server verifies their JWS again; nothing is granted here.
public struct StoreKitStoreRepository: StoreRepository {
    private let productID: String

    public init(productID: String = "app.keepwell.coffee") {
        self.productID = productID
    }

    public func displayPrice() async -> String? {
        try? await Product.products(for: [productID]).first?.displayPrice
    }

    public func purchase() async throws(CloudAccountError) -> StorePurchase? {
        let result: Product.PurchaseResult
        do {
            guard let product = try await Product.products(for: [productID]).first else { throw CloudAccountError.storeFailed }
            result = try await product.purchase()
        } catch {
            throw .storeFailed
        }
        switch result {
        case let .success(verification):
            guard case let .verified(transaction) = verification else { throw .storeFailed }
            return StorePurchase(transactionID: transaction.id, signedTransaction: verification.jwsRepresentation)
        case .pending, .userCancelled:
            return nil
        @unknown default:
            return nil
        }
    }

    public func restore() async throws(CloudAccountError) -> [StorePurchase] {
        do {
            try await AppStore.sync()
        } catch {
            throw .storeFailed
        }
        var purchases: [StorePurchase] = []
        for await verification in Transaction.currentEntitlements {
            if case let .verified(transaction) = verification, transaction.productID == productID, transaction.revocationDate == nil {
                purchases.append(StorePurchase(transactionID: transaction.id, signedTransaction: verification.jwsRepresentation))
            }
        }
        return purchases
    }

    public func unfinished() async -> [StorePurchase] {
        var purchases: [StorePurchase] = []
        for await verification in Transaction.unfinished {
            if case let .verified(transaction) = verification, transaction.productID == productID {
                purchases.append(StorePurchase(transactionID: transaction.id, signedTransaction: verification.jwsRepresentation))
            }
        }
        return purchases
    }

    public func finish(_ purchase: StorePurchase) async {
        for await verification in Transaction.unfinished {
            if case let .verified(transaction) = verification, transaction.id == purchase.transactionID {
                await transaction.finish()
            }
        }
    }
}
