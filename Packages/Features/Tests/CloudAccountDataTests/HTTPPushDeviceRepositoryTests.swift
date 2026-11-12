import CloudAccountData
import CloudAccountDomain
import Foundation
import Testing

@Suite("Push device over HTTP", .serialized)
struct HTTPPushDeviceRepositoryTests {
    private let base = URL(string: "https://api.example.com")!

    private func repository() -> HTTPPushDeviceRepository {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        StubProtocol.requests = []
        let store = InMemorySessionStore()
        store.save("better-auth.session_token=abc")
        return HTTPPushDeviceRepository(client: APIClient(baseURL: base, store: store, configuration: configuration), clientID: "client-1")
    }

    @Test
    func registeringPutsTheDeviceUnderTheInstallationsClientID() async throws {
        let repository = repository()
        StubProtocol.handler = { _ in (204, [:], Data()) }
        try await repository.register(PushDevice(
            token: PushDevice.hex(Data([0xAB, 0x01, 0xFF])), timeZone: "America/Managua", locale: "es-NI", environment: .sandbox,
        ))
        let request = try #require(StubProtocol.requests.first)
        #expect(request.httpMethod == "PUT")
        #expect(request.url?.path == "/push/devices/client-1")
        #expect(request.value(forHTTPHeaderField: "Cookie") == "better-auth.session_token=abc")
        let body = try #require(request.httpBody)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: String])
        #expect(json == [
            "platform": "ios", "token": "ab01ff", "time_zone": "America/Managua", "locale": "es-NI", "environment": "sandbox",
        ])
    }

    @Test
    func unregisteringDeletesIt() async throws {
        let repository = repository()
        StubProtocol.handler = { _ in (204, [:], Data()) }
        try await repository.unregister()
        let request = try #require(StubProtocol.requests.first)
        #expect(request.httpMethod == "DELETE")
        #expect(request.url?.path == "/push/devices/client-1")
    }

    @Test
    func aLostSessionAndAMissingPlanAreTold() async {
        let repository = repository()
        let device = PushDevice(token: "ab", timeZone: "UTC", locale: "en", environment: .production)
        StubProtocol.handler = { _ in (401, [:], Data()) }
        await #expect(throws: CloudAccountError.signedOut) { try await repository.register(device) }
        StubProtocol.handler = { _ in (403, [:], Data()) }
        await #expect(throws: CloudAccountError.needsPlan) { try await repository.register(device) }
    }

    @Test
    func theTokenIsLowercaseHex() {
        #expect(PushDevice.hex(Data([0x00, 0x0F, 0xA0, 0xFF])) == "000fa0ff")
    }
}
