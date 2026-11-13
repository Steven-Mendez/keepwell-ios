import CloudAccountDomain
import Domain
import Foundation

// Builds older than merchants stored pulled movements and rules without their `merchant_id` and
// `via_merchant_id`, and dropped `merchant` rows, without recording a skip: the cursor moved on and
// nothing would bring them back. This build always sends both links (null for none), so its first
// push of such a row would clear on the account a link set on the web or by an assistant. So once,
// before anything goes up, those entities come down again whole.

extension SyncEngine {
    static let merchantResyncKey = "sync.merchantLinksResynced"
    /// Merchants first, so the links that follow name merchants this device has.
    static let merchantLinkEntities = ["merchant", "transaction", "recurringRule", "categorizationRule"]

    /// A first sync (or a resolved conflict) brings everything in its snapshot.
    func markMerchantLinksResynced() {
        defaults.set(true, forKey: Self.merchantResyncKey)
    }

    /// Rows with no pending change are adopted as the server's truth, as a pull would. A row with a
    /// pending change keeps it (the existing conflict rule), but the links it lacks are filled in,
    /// in the record and in its pending events, so pushing it doesn't clear them. Nothing is marked
    /// done until every row is applied: a failure tries again on the next round, and nothing is
    /// pushed meanwhile.
    func resyncMerchantLinks() async throws(CloudAccountError) {
        guard cursor != nil, !defaults.bool(forKey: Self.merchantResyncKey) else { return }
        var rows: [RemoteRow] = []
        for entity in Self.merchantLinkEntities {
            rows += try await Self.fetchEntity(entity, client: client).rows
        }
        for remoteRow in rows {
            guard let id = (try? JSONSerialization.jsonObject(with: remoteRow.row) as? [String: Any])?["id"] as? String else {
                continue
            }
            guard await store.hasPendingEvent(entity: remoteRow.entity, entityID: id) else {
                try await adopt(entity: remoteRow.entity, data: remoteRow.row)
                continue
            }
            do {
                try await store.fillMissingMerchantLinks(entity: remoteRow.entity, row: remoteRow.row)
            } catch {
                if case .persistence = error {
                    throw .server(code: "apply_failed", requestID: nil)
                }
                recordSkipped(entity: remoteRow.entity, id: id, error: error)
            }
        }
        markMerchantLinksResynced()
    }
}
