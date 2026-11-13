import CloudAccountDomain
import Domain
import Foundation

// The repairs after every pull, as keepwell-web runs them.

extension SyncEngine {
    /// A movement edited here before the pull brought its category's deletion keeps the deleted id
    /// (its later edit won). It moves to "Other" now, through the outbox, so the account gets it too.
    func repairDeletedCategories() async throws(CloudAccountError) {
        guard let repairCategories else { return }
        do {
            try await repairCategories.execute(deletedCategoryIDs: store.deletedCategoryIDs())
        } catch {
            throw .server(code: "local_write_failed", requestID: nil)
        }
    }

    /// The same for merchants: a link to one deleted elsewhere is removed, through the outbox.
    func repairDeletedMerchants() async throws(CloudAccountError) {
        guard let repairMerchants else { return }
        do {
            try await repairMerchants.execute(deletedMerchantIDs: store.deletedMerchantIDs())
        } catch {
            throw .server(code: "local_write_failed", requestID: nil)
        }
    }
}
