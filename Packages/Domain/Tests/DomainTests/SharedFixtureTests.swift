import Foundation
import Testing
@testable import Domain

/// The vectors keepwell-web and keepwell-api run too. If one fails, an id rule changed in one
/// copy and not in the others: sync would stop merging the same occurrence or installment.
@Suite("Shared id fixtures")
struct SharedFixtureTests {
    private struct IDs: Decodable {
        struct Vector: Decodable {
            let name: String
            let namespace: UUID
            let id: UUID
        }

        struct Rule: Decodable {
            let id: UUID
            let startDate: String
            let frequency: RecurringFrequency
            let interval: Int
        }

        struct Occurrence: Decodable {
            let rule: Rule
            let index: Int
            let id: UUID
        }

        struct Payment: Decodable {
            let loanId: UUID
            let number: Int
            let id: UUID
        }

        let namespace: UUID
        let uuidV5: [Vector]
        let occurrences: [Occurrence]
        let loanPayments: [Payment]
    }

    private func load() throws -> IDs {
        let url = try #require(Bundle.module.url(forResource: "ids", withExtension: "json", subdirectory: "Fixtures"))
        return try JSONDecoder().decode(IDs.self, from: Data(contentsOf: url))
    }

    @Test
    func namespaceIsUUIDv5OfKeepwell() throws {
        let fixtures = try load()
        #expect(NameBasedID.keepwellNamespace == fixtures.namespace)
    }

    @Test
    func uuidV5MatchesTheSharedVectors() throws {
        for vector in try load().uuidV5 {
            #expect(NameBasedID.uuidV5(vector.name, namespace: vector.namespace) == vector.id, "\(vector.name)")
        }
    }

    @Test
    func occurrenceAndInstallmentIDsMatchTheWeb() throws {
        let fixtures = try load()
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        for occurrence in fixtures.occurrences {
            let start = try #require(parser.date(from: occurrence.rule.startDate))
            #expect(NameBasedID.isoMilliseconds(start) == occurrence.rule.startDate)
            let id = NameBasedID.occurrence(
                ruleID: occurrence.rule.id,
                startDate: start,
                frequency: occurrence.rule.frequency,
                interval: occurrence.rule.interval,
                index: occurrence.index,
            )
            #expect(id == occurrence.id)
        }
        for payment in fixtures.loanPayments {
            #expect(NameBasedID.loanPayment(loanID: payment.loanId, number: payment.number) == payment.id)
        }
    }
}

@Suite("Deterministic occurrences")
struct DeterministicOccurrenceTests {
    @Test
    func twoDevicesRecordTheSameOccurrenceAsOneMovement() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Managua"))
        let start = try #require(calendar.date(from: DateComponents(year: 2026, month: 1, day: 31, hour: 9)))
        let rule = RecurringRule(
            name: "Alquiler", kind: .expense, categoryID: "housing", amount: 450, currency: "USD",
            accountID: UUID(), frequency: .monthly, interval: 1, startDate: start, nextDate: start,
            isSubscription: false, autoConfirm: true,
        )
        let rate = try ExchangeRate(principal: "USD", second: "NIO", rate: 36)
        let today = try #require(calendar.date(byAdding: .month, value: 2, to: start))
        let first = RecurringSchedule.materialize([rule], transactions: [], today: today, exchangeRate: rate, calendar: calendar)
        let second = RecurringSchedule.materialize([rule], transactions: [], today: today, exchangeRate: rate, calendar: calendar)
        #expect(first.transactions.map(\.id) == second.transactions.map(\.id))
        #expect(first.transactions.count == 3)
        // Feb 28 is index 1 even though it was clamped from the 31st.
        let february = try #require(first.transactions.dropFirst().first)
        #expect(RecurringSchedule.occurrenceIndex(of: rule, on: february.date, calendar: calendar) == 1)
        #expect(february.id == NameBasedID.occurrence(ruleID: rule.id, startDate: start, frequency: .monthly, interval: 1, index: 1))
    }
}
