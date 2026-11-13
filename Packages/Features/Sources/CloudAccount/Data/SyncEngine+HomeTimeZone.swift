import CloudAccountDomain
import Domain
import Foundation

extension SyncEngine {
    /// Sets the home time zone from this iPhone when the account has none yet. Only after a pull:
    /// a zone set on another device has arrived by then and is kept.
    func fillHomeTimeZone() async throws(CloudAccountError) -> Bool {
        guard let fillTimeZone else { return false }
        do {
            return try await fillTimeZone.execute()
        } catch {
            throw .server(code: "local_write_failed", requestID: nil)
        }
    }

    /// The case, without values that could be the person's data (an amount in a message, say).
    /// A missing or malformed wire field is named, as it says what changed.
    static func reason(for error: DomainError) -> String {
        if case let .corruptedData(message) = error {
            return message.hasPrefix("wire ") ? "corruptedData: \(message)" : "corruptedData"
        }
        return Mirror(reflecting: error).children.first?.label ?? String(describing: error)
    }
}
