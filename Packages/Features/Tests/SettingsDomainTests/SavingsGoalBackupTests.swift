import Domain
import DomainSamples
import Foundation
import Testing
@testable import SettingsDomain

@Suite("Backup of savings goals")
struct SavingsGoalBackupTests {
    private let sample = SampleData.standard
    private let stamp = RecordMetadata(
        createdAt: Date(timeIntervalSince1970: 1_793_000_000),
        updatedAt: Date(timeIntervalSince1970: 1_793_000_000.5),
    )

    private func json(_ data: Data) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    /// A goal with every field and one with none of the optional ones, with fixed values, so the
    /// exact text both apps write is pinned here.
    private func fixedContents() throws -> BackupContents {
        let trip = try SavingsGoal(
            id: #require(UUID(uuidString: "7A1B2C3D-4E5F-4061-8273-8495A6B7C8D9")),
            name: "Viaje",
            target: Money(15000, "NIO"),
            saved: Decimal(string: "2500.5") ?? 0,
            targetMonth: TargetMonth(month: 12, year: 2026),
            icon: "airplane",
            color: "blue",
        )
        let fund = try SavingsGoal(
            id: #require(UUID(uuidString: "1B2C3D4E-5F60-4172-8384-95A6B7C8D9E0")),
            name: "Emergency fund",
            target: Money(3000, "USD"),
        )
        let deleted = RecordMetadata(createdAt: stamp.createdAt, updatedAt: stamp.updatedAt, deletedAt: stamp.updatedAt)
        return BackupContents(
            settings: Stamped(sample.settings, stamp),
            accounts: sample.accounts.map { Stamped($0, stamp) },
            cards: sample.cards.map { Stamped($0, stamp) },
            categories: sample.categories.map { Stamped($0, stamp) },
            transactions: [],
            savingsGoals: [Stamped(trip, stamp), Stamped(fund, deleted)],
        )
    }

    @Test
    func goalsAreWrittenWithTheSharedKeysInSchemaThree() throws {
        let data = try #require(BackupSnapshot(contents: fixedContents(), exportedAt: stamp.createdAt)).encoded()
        let text = try #require(String(data: data, encoding: .utf8))
        // The same text the web app writes: keys sorted, empty optionals left out, exact decimals.
        let trip = """
        {"color":"blue","createdAt":"2026-10-26T07:33:20.000Z","icon":"airplane",\
        "id":"7a1b2c3d-4e5f-4061-8273-8495a6b7c8d9","name":"Viaje","saved":"2500.5",\
        "target":{"amount":"15000","currency":"NIO"},"targetMonth":{"month":12,"year":2026},\
        "updatedAt":"2026-10-26T07:33:20.500Z"}
        """
        let fund = """
        {"createdAt":"2026-10-26T07:33:20.000Z","deletedAt":"2026-10-26T07:33:20.500Z",\
        "id":"1b2c3d4e-5f60-4172-8384-95a6b7c8d9e0","name":"Emergency fund","saved":"0",\
        "target":{"amount":"3000","currency":"USD"},"updatedAt":"2026-10-26T07:33:20.500Z"}
        """
        #expect(text.contains("\"savingsGoals\":[\(trip),\(fund)]"))
        #expect(try json(data)["schemaVersion"] as? Int == 3)
        #expect(BackupSnapshot.currentSchemaVersion == 3)
    }

    @Test
    func goalsRoundTripWithTheirDeletions() async throws {
        let contents = try fixedContents()
        let data = try #require(BackupSnapshot(contents: contents, exportedAt: .now)).encoded()
        let decoded = try BackupSnapshot.decode(data).contents()
        #expect(decoded.savingsGoals == contents.savingsGoals)

        let store = InMemoryStore()
        _ = try await DefaultRestoreBackupUseCase(store: store).execute(data)
        #expect(await store.fetchSavingsGoals() == contents.savingsGoals.filter { !$0.metadata.isDeleted }.map(\.value))
    }

    @Test
    func aVersionTwoFileStillRestoresWithNoGoals() async throws {
        var file = try json(#require(BackupSnapshot(contents: fixedContents(), exportedAt: .now)).encoded())
        file["schemaVersion"] = 2
        file.removeValue(forKey: "savingsGoals")
        let store = InMemoryStore(sample: sample)
        let summary = try await DefaultRestoreBackupUseCase(store: store).execute(JSONSerialization.data(withJSONObject: file))
        #expect(summary.accounts == sample.accounts.count)
        #expect(await store.fetchSavingsGoals().isEmpty)
    }

    enum Damage: String, CaseIterable {
        case zeroTarget
        case negativeTarget
        case negativeSaved
        case monthOutOfRange

        func apply(to goal: inout [String: Any]) {
            switch self {
            case .zeroTarget: goal["target"] = ["amount": "0", "currency": "NIO"]
            case .negativeTarget: goal["target"] = ["amount": "-5", "currency": "NIO"]
            case .negativeSaved: goal["saved"] = "-0.01"
            case .monthOutOfRange: goal["targetMonth"] = ["month": 13, "year": 2026]
            }
        }
    }

    @Test(arguments: Damage.allCases)
    func anInvalidGoalIsRefusedAndNothingChanges(damage: Damage) async throws {
        var file = try json(#require(BackupSnapshot(contents: fixedContents(), exportedAt: .now)).encoded())
        var goals = try #require(file["savingsGoals"] as? [[String: Any]])
        damage.apply(to: &goals[0])
        file["savingsGoals"] = goals
        let store = InMemoryStore(sample: sample)
        await #expect(throws: DomainError.self) {
            _ = try await DefaultRestoreBackupUseCase(store: store).execute(JSONSerialization.data(withJSONObject: file))
        }
        #expect(await store.fetchSavingsGoals() == sample.savingsGoals)
    }
}
