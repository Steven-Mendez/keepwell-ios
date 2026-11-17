import Domain
import DomainSamples
import Foundation
import Testing
@testable import SettingsDomain

@Suite("Shared expenses in the CSV")
struct SharedExpenseCSVTests {
    @Test
    func theCSVMarksASplitExpenseShared() {
        let ledger = SharedExpenseLedger()
        let csv = DefaultExportTransactionsUseCase.csv(
            transactions: [ledger.shared, ledger.groceries], accounts: [], cards: [], categories: TransactionCategory.defaults,
            debts: ledger.debts,
        )
        let rows = csv.split(separator: "\n").dropFirst()
        let shared = rows.map { $0.split(separator: ",", omittingEmptySubsequences: false)[12] }
        #expect(shared == ["no", "yes"])
    }
}
