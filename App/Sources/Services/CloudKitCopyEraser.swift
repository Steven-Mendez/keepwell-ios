import CloudKit
import Domain
import Foundation
import SettingsDomain

/// Deletes the record zone SwiftData mirrors into, which removes every synced record at once.
/// It runs whether iCloud is on or off now: a copy uploaded while it was on stays in iCloud.
struct CloudKitCopyEraser: CloudCopyEraser {
    /// The zone `NSPersistentCloudKitContainer` creates in the private database.
    static let zoneID = CKRecordZone.ID(zoneName: "com.apple.coredata.cloudkit.zone")

    let containerIdentifier: String

    func eraseCloudCopy() async throws(DomainError) {
        // Builds signed without iCloud never had a copy, and asking for the container would stop the app.
        guard !containerIdentifier.isEmpty, await SigningEntitlements.current.allowsCloudKit(container: containerIdentifier) else { return }
        let container = CKContainer(identifier: containerIdentifier)
        // Signed out: there is no copy this device can reach.
        guard await (try? container.accountStatus()) == .available else { return }
        do {
            _ = try await container.privateCloudDatabase.deleteRecordZone(withID: Self.zoneID)
        } catch let error as CKError where error.code == .zoneNotFound || error.code == .userDeletedZone {
            return
        } catch {
            throw .persistence("iCloud copy not deleted: \(error)")
        }
    }
}
