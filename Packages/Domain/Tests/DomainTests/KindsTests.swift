import CustomDump
import Foundation
import Testing
@testable import Domain

@Suite("Domain vocabulary")
struct KindsTests {
    @Test
    func rawValuesMatchHandoff() {
        expectNoDifference(TransactionKind.allCases.map(\.rawValue), ["expense", "income", "transfer"])
        expectNoDifference(TransactionStatus.allCases.map(\.rawValue), ["confirmed", "planned"])
    }

    @Test(arguments: TransactionKind.allCases)
    func transactionKindRoundTripsThroughJSON(kind: TransactionKind) throws {
        let data = try JSONEncoder().encode(kind)
        #expect(try JSONDecoder().decode(TransactionKind.self, from: data) == kind)
    }
}
