import CloudAccountDomain
import Foundation

/// `PUT` and `DELETE /push/devices/:clientId`, keyed by the installation's sync `client_id` so the
/// same device is one row however often it registers.
public struct HTTPPushDeviceRepository: PushDeviceRepository {
    private let client: APIClient
    private let clientID: String

    public init(client: APIClient, clientID: String) {
        self.client = client
        self.clientID = clientID
    }

    private struct Body: Encodable, Sendable {
        let platform = "ios"
        let token: String
        let time_zone: String // swiftlint:disable:this identifier_name
        let locale: String
        let environment: String
    }

    private var path: String {
        "push/devices/\(clientID)"
    }

    public func register(_ device: PushDevice) async throws(CloudAccountError) {
        let body = Body(token: device.token, time_zone: device.timeZone, locale: device.locale, environment: device.environment.rawValue)
        try await check(client.send("PUT", path, json: body))
    }

    public func unregister() async throws(CloudAccountError) {
        try await check(client.send("DELETE", path))
    }

    private func check(_ response: APIClient.Response) throws(CloudAccountError) {
        switch response.status {
        case 200 ..< 300: return
        case 401: throw .signedOut
        case 403: throw .needsPlan
        default: throw .server(code: "http_\(response.status)", requestID: nil)
        }
    }
}
