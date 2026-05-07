import Foundation
import GRDB
import Testing
@testable import ZseCore

struct TransactionServiceTests {

    // MARK: - createDeposit

    @Test
    func createDepositPersistsCorrectEntries() throws {
        let h = try TransactionHarness()
        defer { h.cleanup() }

        try h.transactionService.createDeposit(
            currentAccountID: h.bankAccountID,
            incomeCategoryAccountID: h.incomeAccountID,
            date: "2026-01-10",
            description: "Salary",
            state: "cleared",
            amount: 500_000,
            partnerName: nil,
            memo: nil
        )

        let ledger = try h.transactionRepository.fetchTransactions(forAccountID: h.bankAccountID)
        #expect(ledger.count == 1, "Expected one ledger row after deposit")
        #expect(ledger[0].inAmount == 500_000, "Expected deposit to appear as inflow on bank account")
        #expect(ledger[0].outAmount == nil, "Expected no outflow on bank account for a deposit")
        #expect(ledger[0].runningBalance == 500_000, "Expected running balance to equal deposit amount")
        #expect(ledger[0].state == "cleared", "Expected persisted state to match")
    }

    @Test
    func createDepositWithWrongCounterpartClassThrows() throws {
        let h = try TransactionHarness()
        defer { h.cleanup() }

        #expect(throws: (any Error).self) {
            try h.transactionService.createDeposit(
                currentAccountID: h.bankAccountID,
                incomeCategoryAccountID: h.expenseAccountID,
                date: "2026-01-10",
                description: "Misrouted",
                state: "uncleared",
                amount: 1000,
                partnerName: nil,
                memo: nil
            )
        }
    }

    // MARK: - createSpending

    @Test
    func createSpendingPersistsCorrectEntries() throws {
        let h = try TransactionHarness()
        defer { h.cleanup() }

        try h.transactionService.createSpending(
            currentAccountID: h.bankAccountID,
            expenseCategoryAccountID: h.expenseAccountID,
            date: "2026-02-01",
            description: "Grocery run",
            state: "cleared",
            amount: 12_500,
            partnerName: "Spar",
            memo: nil
        )

        let ledger = try h.transactionRepository.fetchTransactions(forAccountID: h.bankAccountID)
        #expect(ledger.count == 1, "Expected one ledger row after spending")
        #expect(ledger[0].outAmount == 12_500, "Expected spending to appear as outflow on bank account")
        #expect(ledger[0].inAmount == nil, "Expected no inflow on bank account for spending")
        #expect(ledger[0].partnerName == "Spar", "Expected partner name to be stored")
        #expect(ledger[0].runningBalance == -12_500, "Expected running balance to be negative after spending")
    }

    @Test
    func createSpendingWithWrongCounterpartClassThrows() throws {
        let h = try TransactionHarness()
        defer { h.cleanup() }

        #expect(throws: (any Error).self) {
            try h.transactionService.createSpending(
                currentAccountID: h.bankAccountID,
                expenseCategoryAccountID: h.incomeAccountID,
                date: "2026-02-01",
                description: "Misrouted spending",
                state: "uncleared",
                amount: 1000,
                partnerName: nil,
                memo: nil
            )
        }
    }

    // MARK: - createTransfer

    @Test
    func createSameCurrencyTransferUpdatesLedgersOnBothSides() throws {
        let h = try TransactionHarness()
        defer { h.cleanup() }

        try h.transactionService.createTransfer(
            sourceAccountID: h.bankAccountID,
            targetAccountID: h.cashAccountID,
            sourceAmount: 30_000,
            targetAmount: nil,
            date: "2026-03-01",
            description: "Pocket money",
            state: "cleared",
            partnerName: nil,
            memo: nil
        )

        let bankLedger = try h.transactionRepository.fetchTransactions(forAccountID: h.bankAccountID)
        let cashLedger = try h.transactionRepository.fetchTransactions(forAccountID: h.cashAccountID)

        #expect(bankLedger.count == 1)
        #expect(cashLedger.count == 1)
        #expect(bankLedger[0].outAmount == 30_000, "Expected bank account to show outflow")
        #expect(cashLedger[0].inAmount == 30_000, "Expected cash account to show inflow")
        #expect(bankLedger[0].runningBalance == -30_000)
        #expect(cashLedger[0].runningBalance == 30_000)
    }

    @Test
    func createCrossCurrencyTransferPersistsDistinctAmounts() throws {
        let h = try TransactionHarness()
        defer { h.cleanup() }

        try h.transactionService.createTransfer(
            sourceAccountID: h.bankAccountID,
            targetAccountID: h.eurAccountID,
            sourceAmount: 40_000,
            targetAmount: 100,
            date: "2026-03-15",
            description: "FX transfer",
            state: "uncleared",
            partnerName: nil,
            memo: nil
        )

        let entryCurrencies = try h.databaseManager.dbQueue.read { db in
            try Row.fetchAll(db, sql: "SELECT amount, currency FROM entries ORDER BY id")
        }

        #expect(entryCurrencies.count == 2, "Expected exactly two entries for a cross-currency transfer")
        let amounts = entryCurrencies.map { $0["amount"] as Double? }
        #expect(amounts.contains(100), "Expected EUR target amount entry")
        #expect(amounts.contains(-40_000), "Expected HUF source amount entry")
    }

    @Test
    func createSameCurrencyTransferWithAmountMismatchThrows() throws {
        let h = try TransactionHarness()
        defer { h.cleanup() }

        #expect(throws: (any Error).self) {
            try h.transactionService.createTransfer(
                sourceAccountID: h.bankAccountID,
                targetAccountID: h.cashAccountID,
                sourceAmount: 10_000,
                targetAmount: 9_000,
                date: "2026-03-20",
                description: "Mismatch",
                state: "uncleared",
                partnerName: nil,
                memo: nil
            )
        }
    }

    @Test
    func createTransferWithSameAccountThrows() throws {
        let h = try TransactionHarness()
        defer { h.cleanup() }

        #expect(throws: (any Error).self) {
            try h.transactionService.createTransfer(
                sourceAccountID: h.bankAccountID,
                targetAccountID: h.bankAccountID,
                sourceAmount: 5_000,
                targetAmount: nil,
                date: "2026-03-20",
                description: "Self-transfer",
                state: "uncleared",
                partnerName: nil,
                memo: nil
            )
        }
    }

    // MARK: - deleteTransaction

    @Test
    func deleteUnclearedTransactionRemovesIt() throws {
        let h = try TransactionHarness()
        defer { h.cleanup() }

        let txn = try h.transactionService.createSpending(
            currentAccountID: h.bankAccountID,
            expenseCategoryAccountID: h.expenseAccountID,
            date: "2026-04-01",
            description: "To delete",
            state: "uncleared",
            amount: 1_000,
            partnerName: nil,
            memo: nil
        )

        let txnID = try #require(txn.id)
        try h.transactionService.deleteTransaction(transactionID: txnID)

        let remaining = try h.transactionRepository.fetchTransactions(forAccountID: h.bankAccountID)
        #expect(remaining.isEmpty, "Expected ledger to be empty after deletion")
    }

    @Test
    func deleteClearedTransactionThrows() throws {
        let h = try TransactionHarness()
        defer { h.cleanup() }

        let txn = try h.transactionService.createSpending(
            currentAccountID: h.bankAccountID,
            expenseCategoryAccountID: h.expenseAccountID,
            date: "2026-04-02",
            description: "Cleared, cannot delete",
            state: "cleared",
            amount: 2_000,
            partnerName: nil,
            memo: nil
        )

        let txnID = try #require(txn.id)

        #expect(throws: (any Error).self) {
            try h.transactionService.deleteTransaction(transactionID: txnID)
        }

        let remaining = try h.transactionRepository.fetchTransactions(forAccountID: h.bankAccountID)
        #expect(remaining.count == 1, "Expected cleared transaction to survive failed deletion attempt")
    }

    // MARK: - duplicateTransaction

    @Test
    func duplicateTransactionCreatesUnclearedCopy() throws {
        let h = try TransactionHarness()
        defer { h.cleanup() }

        let original = try h.transactionService.createSpending(
            currentAccountID: h.bankAccountID,
            expenseCategoryAccountID: h.expenseAccountID,
            date: "2026-04-10",
            description: "Original",
            state: "cleared",
            amount: 5_000,
            partnerName: nil,
            memo: nil
        )

        let originalID = try #require(original.id)
        let duplicate = try h.transactionService.duplicateTransaction(transactionID: originalID)
        let duplicateID = try #require(duplicate.id)

        #expect(duplicateID != originalID, "Expected duplicate to get a distinct ID")
        #expect(duplicate.state == "uncleared", "Expected duplicate to always start as uncleared")
        #expect(duplicate.txnDate == original.txnDate, "Expected duplicate to keep original date")
        #expect(duplicate.description == original.description, "Expected duplicate to keep original description")

        let ledger = try h.transactionRepository.fetchTransactions(forAccountID: h.bankAccountID)
        #expect(ledger.count == 2, "Expected both original and duplicate in the ledger")
    }

    // MARK: - changeTransactionState

    @Test
    func changeTransactionStateUpdatesPersistedState() throws {
        let h = try TransactionHarness()
        defer { h.cleanup() }

        let txn = try h.transactionService.createSpending(
            currentAccountID: h.bankAccountID,
            expenseCategoryAccountID: h.expenseAccountID,
            date: "2026-04-20",
            description: "State change",
            state: "uncleared",
            amount: 3_000,
            partnerName: nil,
            memo: nil
        )

        let txnID = try #require(txn.id)
        try h.transactionService.changeTransactionState(transactionID: txnID, state: "cleared")

        let row = try h.databaseManager.dbQueue.read { db in
            try Row.fetchOne(
                db,
                sql: "SELECT state, status_warning_flag FROM transactions WHERE id = ?",
                arguments: [txnID]
            )
        }

        #expect(row?["state"] as String? == "cleared", "Expected state to update to cleared")
        #expect(row?["status_warning_flag"] as Bool? == false, "Expected warning flag to clear after state change")
    }
}

// MARK: - Harness

private final class TransactionHarness {
    let tempDirectoryURL: URL
    let databaseManager: DatabaseManager
    let transactionRepository: TransactionRepository
    let transactionService: TransactionService

    let bankAccountID: Int64
    let cashAccountID: Int64
    let eurAccountID: Int64
    let incomeAccountID: Int64
    let expenseAccountID: Int64

    init() throws {
        tempDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: tempDirectoryURL,
            withIntermediateDirectories: true
        )

        let databaseURL = tempDirectoryURL.appendingPathComponent("zse-test.sqlite")
        databaseManager = try DatabaseManager(databasePath: databaseURL.path)

        let accountRepository = AccountRepository(databaseManager: databaseManager)
        let partnerRepository = PartnerRepository(databaseManager: databaseManager)
        transactionRepository = TransactionRepository(databaseManager: databaseManager)
        transactionService = TransactionService(
            accountRepository: accountRepository,
            partnerRepository: partnerRepository,
            transactionRepository: transactionRepository
        )

        var bank = Account(
            name: "Erste HUF",
            class: "asset",
            subtype: "bank",
            currency: "HUF",
            isGroup: false,
            includeInNetWorth: true
        )
        try accountRepository.createAccount(&bank)
        bankAccountID = bank.id!

        var cash = Account(
            name: "KP HUF",
            class: "asset",
            subtype: "cash",
            currency: "HUF",
            isGroup: false,
            includeInNetWorth: true
        )
        try accountRepository.createAccount(&cash)
        cashAccountID = cash.id!

        var eur = Account(
            name: "Erste EUR",
            class: "asset",
            subtype: "bank",
            currency: "EUR",
            isGroup: false,
            includeInNetWorth: true
        )
        try accountRepository.createAccount(&eur)
        eurAccountID = eur.id!

        var income = Account(
            name: "Salary",
            class: "income",
            subtype: "group",
            currency: "HUF",
            isGroup: false,
            includeInNetWorth: false
        )
        try accountRepository.createAccount(&income)
        incomeAccountID = income.id!

        var expense = Account(
            name: "Groceries",
            class: "expense",
            subtype: "group",
            currency: "HUF",
            isGroup: false,
            includeInNetWorth: false
        )
        try accountRepository.createAccount(&expense)
        expenseAccountID = expense.id!
    }

    func cleanup() {
        try? databaseManager.close()
        try? FileManager.default.removeItem(at: tempDirectoryURL)
    }
}
