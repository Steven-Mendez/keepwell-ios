import Domain
import DomainSamples
import Foundation
import Testing
@testable import SettingsDomain

@Suite("Backup of loans and personal debts")
struct DebtBackupTests {
    private let sample = SampleData.standard
    private let stamp = RecordMetadata(
        createdAt: Date(timeIntervalSince1970: 1_793_000_000),
        updatedAt: Date(timeIntervalSince1970: 1_793_000_000.5),
    )

    private func json(_ data: Data) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func day(_ text: String) throws -> Date {
        try Date.ISO8601FormatStyle().parse(text)
    }

    private func id(_ text: String) throws -> UUID {
        try #require(UUID(uuidString: text))
    }

    /// Every field and none of the optional ones, with fixed values, so the exact text both apps
    /// write is pinned here (and in the web's `debts.test.ts`).
    private func fixedLoans() throws -> (moto: Loan, phone: Loan) {
        let moto = try Loan(
            id: id("2A3B4C5D-6E7F-4081-9293-A4B5C6D7E8F9"),
            name: "Moto",
            lender: "Banpro",
            borrowed: Money(60000, "NIO"),
            installmentAmount: Decimal(string: "5500.5") ?? 0,
            installmentCount: 12,
            frequency: .monthly,
            firstDueDate: day("2026-11-28T18:00:00Z"),
            payments: [LoanPayment(
                number: 1,
                paidAt: day("2026-11-27T15:30:00Z"),
                transactionID: id("9C0E1D2F-3A4B-4C5D-8E6F-7A8B9C0D1E2F"),
            )],
        )
        let phone = try Loan(
            id: id("6E7F8091-A2B3-4C4D-95E6-F708192A3B4C"),
            name: "Phone",
            borrowed: Money(800, "USD"),
            installmentAmount: 100,
            installmentCount: 8,
            frequency: .weekly,
            firstDueDate: day("2026-11-02T18:00:00Z"),
        )
        return (moto, phone)
    }

    private func fixedDebts() throws -> [PersonalDebt] {
        let juan = try PersonalDebt(
            id: id("3B4C5D6E-7F80-4192-A3B4-C5D6E7F8091A"),
            person: "Juan",
            direction: .theyOweMe,
            amount: Money(500, "NIO"),
            date: day("2026-11-12T18:00:00Z"),
            note: "Pizza",
            repayments: [DebtRepayment(amount: Decimal(string: "200.5") ?? 0, date: day("2026-11-15T18:00:00Z"))],
            transactionID: id("4C5D6E7F-8091-4A2B-B3C4-D5E6F708192A"),
        )
        let ana = try PersonalDebt(
            id: id("5D6E7F80-91A2-4B3C-84D5-E6F708192A3B"),
            person: "Ana",
            direction: .iOwe,
            amount: Money(40, "USD"),
            date: day("2026-11-05T18:00:00Z"),
            settledAt: day("2026-11-06T18:00:00Z"),
        )
        return [juan, ana]
    }

    private func fixedContents() throws -> BackupContents {
        let (moto, phone) = try fixedLoans()
        let deleted = RecordMetadata(createdAt: stamp.createdAt, updatedAt: stamp.updatedAt, deletedAt: stamp.updatedAt)
        return try BackupContents(
            settings: Stamped(sample.settings, stamp),
            accounts: sample.accounts.map { Stamped($0, stamp) },
            cards: sample.cards.map { Stamped($0, stamp) },
            categories: sample.categories.map { Stamped($0, stamp) },
            transactions: [],
            loans: [Stamped(moto, stamp), Stamped(phone, deleted)],
            personalDebts: fixedDebts().map { Stamped($0, stamp) },
        )
    }

    @Test
    func loansAndDebtsAreWrittenWithTheSharedKeysInSchemaFour() throws {
        let data = try #require(BackupSnapshot(contents: fixedContents(), exportedAt: stamp.createdAt)).encoded()
        let text = try #require(String(data: data, encoding: .utf8))
        // The same text the web app writes: keys sorted, empty optionals left out, exact decimals.
        let loans = """
        "loans":[{"borrowed":{"amount":"60000","currency":"NIO"},"createdAt":"2026-10-26T07:33:20.000Z",\
        "firstDueDate":"2026-11-28T18:00:00.000Z","frequency":"monthly","id":"2a3b4c5d-6e7f-4081-9293-a4b5c6d7e8f9",\
        "installmentAmount":"5500.5","installmentCount":12,"lender":"Banpro","name":"Moto",\
        "payments":[{"number":1,"paidAt":"2026-11-27T15:30:00.000Z","transactionId":"9c0e1d2f-3a4b-4c5d-8e6f-7a8b9c0d1e2f"}],\
        "updatedAt":"2026-10-26T07:33:20.500Z"},\
        {"borrowed":{"amount":"800","currency":"USD"},"createdAt":"2026-10-26T07:33:20.000Z",\
        "deletedAt":"2026-10-26T07:33:20.500Z","firstDueDate":"2026-11-02T18:00:00.000Z","frequency":"weekly",\
        "id":"6e7f8091-a2b3-4c4d-95e6-f708192a3b4c","installmentAmount":"100","installmentCount":8,"name":"Phone",\
        "payments":[],"updatedAt":"2026-10-26T07:33:20.500Z"}]
        """
        let debts = """
        "personalDebts":[{"amount":{"amount":"500","currency":"NIO"},"createdAt":"2026-10-26T07:33:20.000Z",\
        "date":"2026-11-12T18:00:00.000Z","direction":"theyOweMe","id":"3b4c5d6e-7f80-4192-a3b4-c5d6e7f8091a",\
        "note":"Pizza","person":"Juan","repayments":[{"amount":"200.5","date":"2026-11-15T18:00:00.000Z"}],\
        "transactionId":"4c5d6e7f-8091-4a2b-b3c4-d5e6f708192a","updatedAt":"2026-10-26T07:33:20.500Z"},\
        {"amount":{"amount":"40","currency":"USD"},"createdAt":"2026-10-26T07:33:20.000Z",\
        "date":"2026-11-05T18:00:00.000Z","direction":"iOwe","id":"5d6e7f80-91a2-4b3c-84d5-e6f708192a3b",\
        "person":"Ana","repayments":[],"settledAt":"2026-11-06T18:00:00.000Z","updatedAt":"2026-10-26T07:33:20.500Z"}]
        """
        #expect(text.contains(loans))
        #expect(text.contains(debts))
        #expect(try json(data)["schemaVersion"] as? Int == 4)
        #expect(BackupSnapshot.currentSchemaVersion == 4)
    }

    @Test
    func loansAndDebtsRoundTripWithTheirDeletions() async throws {
        let contents = try fixedContents()
        let data = try #require(BackupSnapshot(contents: contents, exportedAt: .now)).encoded()
        let decoded = try BackupSnapshot.decode(data).contents()
        #expect(decoded.loans == contents.loans)
        #expect(decoded.personalDebts == contents.personalDebts)

        let store = InMemoryStore()
        _ = try await DefaultRestoreBackupUseCase(store: store).execute(data)
        #expect(await store.fetchLoans() == [contents.loans[0].value])
        #expect(await store.fetchPersonalDebts() == contents.personalDebts.map(\.value))
    }

    @Test(arguments: [1, 2, 3])
    func anOlderFileStillRestoresWithNoLoansOrDebts(version: Int) async throws {
        var file = try json(#require(BackupSnapshot(contents: fixedContents(), exportedAt: .now)).encoded())
        file["schemaVersion"] = version
        file.removeValue(forKey: "loans")
        file.removeValue(forKey: "personalDebts")
        let store = InMemoryStore(sample: sample)
        let summary = try await DefaultRestoreBackupUseCase(store: store).execute(JSONSerialization.data(withJSONObject: file))
        #expect(summary.accounts == sample.accounts.count)
        #expect(await store.fetchLoans().isEmpty)
        #expect(await store.fetchPersonalDebts().isEmpty)
    }

    enum Damage: String, CaseIterable {
        case zeroInstallment
        case noInstallments
        case paymentOutsideTheSchedule
        case repaidPastTheAmount
        case negativeDebt

        func apply(loan: inout [String: Any], debt: inout [String: Any]) {
            switch self {
            case .zeroInstallment: loan["installmentAmount"] = "0"
            case .noInstallments: loan["installmentCount"] = 0
            case .paymentOutsideTheSchedule: loan["payments"] = [["number": 13, "paidAt": "2026-11-27T15:30:00.000Z"]]
            case .repaidPastTheAmount: debt["repayments"] = [["amount": "500.01", "date": "2026-11-15T18:00:00.000Z"]]
            case .negativeDebt: debt["amount"] = ["amount": "-5", "currency": "NIO"]
            }
        }
    }

    @Test(arguments: Damage.allCases)
    func anInvalidLoanOrDebtIsRefusedAndNothingChanges(damage: Damage) async throws {
        var file = try json(#require(BackupSnapshot(contents: fixedContents(), exportedAt: .now)).encoded())
        var loans = try #require(file["loans"] as? [[String: Any]])
        var debts = try #require(file["personalDebts"] as? [[String: Any]])
        damage.apply(loan: &loans[0], debt: &debts[0])
        file["loans"] = loans
        file["personalDebts"] = debts
        let store = InMemoryStore(sample: sample)
        await #expect(throws: DomainError.self) {
            _ = try await DefaultRestoreBackupUseCase(store: store).execute(JSONSerialization.data(withJSONObject: file))
        }
        #expect(await store.fetchLoans() == sample.loans)
        #expect(await store.fetchPersonalDebts() == sample.personalDebts)
    }
}
