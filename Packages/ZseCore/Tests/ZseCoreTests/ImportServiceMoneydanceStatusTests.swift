import Foundation
import GRDB
import Testing
@testable import ZseCore

struct ImportServiceMoneydanceStatusTests {
    @Test
    func moneydanceStatusColumnSixMapsAtRowAndBlockLevel() throws {
        let cases: [StatusCase] = [
            StatusCase(
                name: "main row uppercase X",
                mainStatus: "X",
                continuationStatus: "",
                expectedState: "cleared"
            ),
            StatusCase(
                name: "continuation row uppercase X",
                mainStatus: "",
                continuationStatus: "X",
                expectedState: "cleared"
            ),
            StatusCase(
                name: "main row lowercase x",
                mainStatus: "x",
                continuationStatus: "",
                expectedState: "reconciling"
            ),
            StatusCase(
                name: "continuation row lowercase x",
                mainStatus: "",
                continuationStatus: "x",
                expectedState: "reconciling"
            ),
            StatusCase(
                name: "empty status on both rows",
                mainStatus: "",
                continuationStatus: "",
                expectedState: "uncleared"
            )
        ]

        for testCase in cases {
            let harness = try ImportHarness()
            defer { harness.cleanup() }

            let parsedFile = try harness.importService.parseFile(at: harness.makeImportFile(for: testCase))
            #expect(parsedFile.transactions.count == 1, "\(testCase.name): expected one parsed transaction")
            #expect(
                parsedFile.transactions[0].state == testCase.expectedState,
                "\(testCase.name): parsed state mismatch"
            )

            let result = try harness.importService.commitImport(parsedFile)
            #expect(result.importedTransactionCount == 1, "\(testCase.name): expected one imported transaction")

            let persistedState = try harness.databaseManager.dbQueue.read { db in
                try String.fetchOne(
                    db,
                    sql: "SELECT state FROM transactions WHERE description = ? LIMIT 1",
                    arguments: ["Ingatlanadó"]
                )
            }

            #expect(
                persistedState == testCase.expectedState,
                "\(testCase.name): persisted state mismatch"
            )
        }
    }

    @Test
    func duplicateMoneydanceTransactionBlocksCollapseToSingleImportedTransaction() throws {
        let harness = try ImportHarness()
        defer { harness.cleanup() }

        let fileURL = try harness.makeDuplicateImportFile()
        let parsedFile = try harness.importService.parseFile(at: fileURL)

        #expect(parsedFile.transactions.count == 2, "Expected parser to preserve both duplicate blocks on a clean import")

        try harness.seedExistingTransaction()

        let result = try harness.importService.commitImport(parsedFile)
        #expect(result.importedTransactionCount == 1, "Expected only one transaction to be imported")

        let persistedRows = try harness.databaseManager.dbQueue.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT description, state FROM transactions WHERE description = 'Ingatlanadó'"
            )
        }

        #expect(persistedRows.count == 1, "Expected only one stored transaction row")
        #expect(persistedRows.first?["state"] as String? == "cleared", "Expected stored state to be cleared")
    }

    @Test
    func mirroredCategorySideBlocksAreIgnored() throws {
        let harness = try ImportHarness()
        defer { harness.cleanup() }

        let fileURL = try harness.makeMirroredCategoryImportFile()
        let parsedFile = try harness.importService.parseFile(at: fileURL)

        #expect(parsedFile.transactions.count == 1, "Expected category-side mirror block to be skipped")
        #expect(parsedFile.transactions[0].state == "cleared", "Expected surviving transaction to keep cleared status")

        let result = try harness.importService.commitImport(parsedFile)
        #expect(result.importedTransactionCount == 1, "Expected only one transaction to be imported")

        let persistedRows = try harness.databaseManager.dbQueue.read { db in
            try Row.fetchAll(db, sql: "SELECT description, state FROM transactions")
        }

        #expect(persistedRows.count == 1, "Expected only one stored transaction row")
        #expect(persistedRows.first?["state"] as String? == "cleared", "Expected stored state to be cleared")
    }

    @Test
    func mirroredTransferBlocksCollapseToSingleImportedTransaction() throws {
        let harness = try ImportHarness()
        defer { harness.cleanup() }

        let fileURL = try harness.makeMirroredTransferImportFile()
        let parsedFile = try harness.importService.parseFile(at: fileURL)

        #expect(parsedFile.transactions.count == 2, "Expected parser to preserve mirrored transfer blocks")

        let result = try harness.importService.commitImport(parsedFile)
        #expect(result.importedTransactionCount == 1, "Expected only one transfer to be imported")

        let persistedRows = try harness.databaseManager.dbQueue.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT description, state FROM transactions WHERE txn_date = '2026-02-11'"
            )
        }

        #expect(persistedRows.count == 1, "Expected only one stored transfer row")
        #expect(persistedRows.first?["state"] as String? == "cleared", "Expected stored transfer state to be cleared")
    }

    @Test
    func importWarningsAreStoredForStatusValidationCases() throws {
        let cases: [WarningCase] = [
            WarningCase(
                name: "line status mismatch",
                occurrenceDate: "2025.09.12",
                mainStatus: "X",
                continuationStatus: "",
                expectedState: "cleared",
                expectedWarningReason: "line_status_mismatch"
            ),
            WarningCase(
                name: "cleared future date",
                occurrenceDate: farFutureDateToken(),
                mainStatus: "X",
                continuationStatus: "X",
                expectedState: "cleared",
                expectedWarningReason: "cleared_future_date"
            ),
            WarningCase(
                name: "pending past date",
                occurrenceDate: "2025.09.12",
                mainStatus: "x",
                continuationStatus: "x",
                expectedState: "reconciling",
                expectedWarningReason: "pending_past_date"
            ),
            WarningCase(
                name: "uncleared past date",
                occurrenceDate: "2025.09.12",
                mainStatus: "",
                continuationStatus: "",
                expectedState: "uncleared",
                expectedWarningReason: "uncleared_past_date"
            )
        ]

        for testCase in cases {
            let harness = try ImportHarness()
            defer { harness.cleanup() }

            let fileURL = try harness.makeWarningImportFile(for: testCase)
            let parsedFile = try harness.importService.parseFile(at: fileURL)

            #expect(parsedFile.transactions.count == 1, "\(testCase.name): expected one parsed transaction")
            #expect(parsedFile.transactions[0].state == testCase.expectedState, "\(testCase.name): state mismatch")
            #expect(parsedFile.transactions[0].statusWarningFlag, "\(testCase.name): warning flag should be set")
            #expect(
                parsedFile.transactions[0].statusWarningReason == testCase.expectedWarningReason,
                "\(testCase.name): warning reason mismatch"
            )

            _ = try harness.importService.commitImport(parsedFile)

            let persisted = try harness.databaseManager.dbQueue.read { db in
                try Row.fetchOne(
                    db,
                    sql: "SELECT state, status_warning_flag, status_warning_reason FROM transactions LIMIT 1"
                )
            }

            #expect(persisted?["state"] as String? == testCase.expectedState, "\(testCase.name): persisted state mismatch")
            #expect(persisted?["status_warning_flag"] as Bool? == true, "\(testCase.name): persisted flag mismatch")
            #expect(
                persisted?["status_warning_reason"] as String? == testCase.expectedWarningReason,
                "\(testCase.name): persisted reason mismatch"
            )
        }
    }

    @Test
    func pendingPastDateOnLiabilityDoesNotRaiseImportWarning() throws {
        let harness = try ImportHarness()
        defer { harness.cleanup() }

        let fileURL = try harness.makePendingCreditCardPurchaseImportFile()
        let parsedFile = try harness.importService.parseFile(at: fileURL)

        #expect(parsedFile.transactions.count == 1, "Expected one credit-card purchase to parse")
        #expect(parsedFile.transactions[0].state == "reconciling", "Expected lowercase x to parse as pending/reconciling")
        #expect(parsedFile.transactions[0].statusWarningReason == "pending_past_date", "Expected parser to flag pending past date before account-class adjustment")

        _ = try harness.importService.commitImport(parsedFile)

        let persisted = try harness.databaseManager.dbQueue.read { db in
            try Row.fetchOne(
                db,
                sql: "SELECT state, status_warning_flag, status_warning_reason FROM transactions LIMIT 1"
            )
        }

        #expect(persisted?["state"] as String? == "reconciling", "Expected liability purchase state to stay pending/reconciling")
        #expect(persisted?["status_warning_flag"] as Bool? == false, "Expected pending past liability purchase not to be marked red")
        #expect(persisted?["status_warning_reason"] as String? == nil, "Expected warning reason to clear for liability purchase")
    }

    @Test
    func manualStatusChangeClearsImportWarning() throws {
        let harness = try ImportHarness()
        defer { harness.cleanup() }

        let fileURL = try harness.makeWarningImportFile(
            for: WarningCase(
                name: "warning clear",
                occurrenceDate: "2025.09.12",
                mainStatus: "",
                continuationStatus: "",
                expectedState: "uncleared",
                expectedWarningReason: "uncleared_past_date"
            )
        )
        let parsedFile = try harness.importService.parseFile(at: fileURL)
        _ = try harness.importService.commitImport(parsedFile)

        let transactionID = try harness.databaseManager.dbQueue.read { db in
            try Int64.fetchOne(db, sql: "SELECT id FROM transactions LIMIT 1")
        }

        #expect(transactionID != nil, "Expected imported transaction to exist")

        try harness.transactionService.changeTransactionState(
            transactionID: transactionID!,
            state: "cleared"
        )

        let persisted = try harness.databaseManager.dbQueue.read { db in
            try Row.fetchOne(
                db,
                sql: "SELECT state, status_warning_flag, status_warning_reason FROM transactions WHERE id = ?",
                arguments: [transactionID!]
            )
        }

        #expect(persisted?["state"] as String? == "cleared", "Expected manual status change to persist")
        #expect(persisted?["status_warning_flag"] as Bool? == false, "Expected warning flag to clear")
        #expect(persisted?["status_warning_reason"] as String? == nil, "Expected warning reason to clear")
    }

    @Test
    func moneydanceStartBalanceImportsIntoLeafAccountOpeningBalance() throws {
        let harness = try ImportHarness()
        defer { harness.cleanup() }

        let fileURL = try harness.makeOpeningBalanceImportFile()
        let parsedFile = try harness.importService.parseFile(at: fileURL)

        #expect(parsedFile.accountDefinitions.count == 1, "Expected one imported account definition")
        #expect(parsedFile.accountDefinitions[0].openingBalance == 504.50, "Expected parsed opening balance")

        _ = try harness.importService.commitImport(parsedFile)

        let importedAccount = try harness.databaseManager.dbQueue.read { db in
            try Account.fetchOne(
                db,
                sql: """
                SELECT *
                FROM accounts
                WHERE name = 'Nóra Erste EUR'
                LIMIT 1
                """
            )
        }

        #expect(importedAccount != nil, "Expected imported leaf account to exist")
        #expect(importedAccount?.openingBalance == 504.50, "Expected opening balance to be stored on leaf account")
        #expect(importedAccount?.openingBalanceDate == nil, "Expected opening balance date to remain nil")
    }

    @Test
    func distinctSameDaySameAmountTransactionsRemainSeparateOnCleanImport() throws {
        let harness = try ImportHarness()
        defer { harness.cleanup() }

        let fileURL = try harness.makeDistinctSameDaySameAmountImportFile()
        let parsedFile = try harness.importService.parseFile(at: fileURL)

        #expect(parsedFile.transactions.count == 2, "Expected both distinct transactions to remain visible in preview")

        let result = try harness.importService.commitImport(parsedFile)
        #expect(result.importedTransactionCount == 2, "Expected both distinct transactions to import into a clean DB")

        let descriptions = try harness.databaseManager.dbQueue.read { db in
            try String.fetchAll(
                db,
                sql: "SELECT description FROM transactions ORDER BY id"
            )
        }

        #expect(descriptions == ["Rita zsebpénz", "Veronika zsebpénz"], "Expected both descriptions to be stored")
    }

    @Test
    func distinctSameDaySameAmountTransactionsRemainSeparateWhenSuppressionIsEnabled() throws {
        let harness = try ImportHarness()
        defer { harness.cleanup() }

        let fileURL = try harness.makeDistinctSameDaySameAmountImportFile()
        let parsedFile = try harness.importService.parseFile(at: fileURL)

        try harness.seedExistingTransaction()

        let result = try harness.importService.commitImport(parsedFile)
        #expect(result.importedTransactionCount == 2, "Expected both distinct transactions to survive suppression")

        let descriptions = try harness.databaseManager.dbQueue.read { db in
            try String.fetchAll(
                db,
                sql: """
                SELECT description
                FROM transactions
                WHERE description IN ('Rita zsebpénz', 'Veronika zsebpénz')
                ORDER BY description
                """
            )
        }

        #expect(descriptions == ["Rita zsebpénz", "Veronika zsebpénz"], "Expected suppression to preserve distinct descriptions")
    }

    @Test
    func transferDuplicatesAreSuppressedOnCleanImport() throws {
        let harness = try ImportHarness()
        defer { harness.cleanup() }

        let fileURL = try harness.makeCleanImportTransferDuplicateFile()
        let parsedFile = try harness.importService.parseFile(at: fileURL)

        #expect(parsedFile.transactions.count == 2, "Expected parser to preserve both mirrored transfer blocks")

        let result = try harness.importService.commitImport(parsedFile)
        #expect(result.importedTransactionCount == 1, "Expected clean import to deduplicate mirrored transfer blocks")

        let persistedRows = try harness.databaseManager.dbQueue.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT description, state FROM transactions WHERE txn_date = '2025-09-23'"
            )
        }

        #expect(persistedRows.count == 1, "Expected only one stored transfer for the clean import batch")
        #expect(persistedRows.first?["state"] as String? == "cleared", "Expected stored transfer state to stay cleared")
    }

    @Test
    func creditCardReimbursementImportsAsTransferAndAppearsOnCardLedger() throws {
        let harness = try ImportHarness()
        defer { harness.cleanup() }

        let fileURL = try harness.makeCreditCardReimbursementImportFile()
        let parsedFile = try harness.importService.parseFile(at: fileURL)

        #expect(parsedFile.transactions.count == 1, "Expected one reimbursement transfer to parse")
        #expect(parsedFile.transactions[0].kind == .sameCurrencyTransfer, "Expected credit-card reimbursement to classify as transfer")
        #expect(parsedFile.transactions[0].counterpartPath == "Erste credit", "Expected credit card to stay the transfer counterpart")

        let result = try harness.importService.commitImport(parsedFile)
        #expect(result.importedTransactionCount == 1, "Expected reimbursement transfer to import")

        let creditAccountID = try harness.databaseManager.dbQueue.read { db in
            try Int64.fetchOne(db, sql: "SELECT id FROM accounts WHERE name = 'Erste credit' LIMIT 1")
        }
        let creditAccountID = try #require(creditAccountID)

        let ledgerItems = try harness.transactionRepository.fetchTransactions(forAccountID: creditAccountID)
        #expect(ledgerItems.count == 1, "Expected reimbursement to appear on the credit-card ledger")
        #expect(ledgerItems[0].inAmount == 12048, "Expected liability reimbursement to display as In on the credit-card ledger")
        #expect(ledgerItems[0].outAmount == nil, "Expected liability reimbursement not to display as Out")
    }

    @Test
    func categoryCounterpartInAccountDefinitionsStillImportsAsExpenseOnCleanImport() throws {
        let harness = try ImportHarness()
        defer { harness.cleanup() }

        let fileURL = try harness.makeCategoryDefinedExpenseImportFile()
        let parsedFile = try harness.importService.parseFile(at: fileURL)

        #expect(parsedFile.transactions.count == 1, "Expected valid expense block to remain in the parsed preview")
        #expect(parsedFile.transactions[0].kind == .expense, "Expected category counterpart to classify as expense, not transfer")

        let result = try harness.importService.commitImport(parsedFile)
        #expect(result.importedTransactionCount == 1, "Expected valid expense to import on a clean DB")

        let persistedRows = try harness.databaseManager.dbQueue.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT description, state FROM transactions WHERE description = 'Veronika'"
            )
        }

        #expect(persistedRows.count == 1, "Expected stored expense transaction to exist")
        #expect(persistedRows.first?["state"] as String? == "cleared", "Expected stored expense to keep cleared status")
    }

    @Test
    func sharedCategoryPathCanImportAcrossMultipleCurrencies() throws {
        let harness = try ImportHarness()
        defer { harness.cleanup() }

        let fileURL = try harness.makeSharedCategoryCrossCurrencyImportFile()
        let parsedFile = try harness.importService.parseFile(at: fileURL)

        #expect(parsedFile.transactions.count == 2, "Expected both cross-currency category transactions to parse")

        let result = try harness.importService.commitImport(parsedFile)
        #expect(result.importedTransactionCount == 2, "Expected both cross-currency category transactions to import")

        let persistedDescriptions = try harness.databaseManager.dbQueue.read { db in
            try String.fetchAll(
                db,
                sql: """
                SELECT description
                FROM transactions
                WHERE description IN ('HUF category tx', 'EUR category tx')
                ORDER BY description
                """
            )
        }

        #expect(persistedDescriptions == ["EUR category tx", "HUF category tx"], "Expected both transactions to be stored")
    }

    @Test
    func parentCategoryWithChildrenRemainsPostableDuringImport() throws {
        let harness = try ImportHarness()
        defer { harness.cleanup() }

        let fileURL = try harness.makeParentCategoryPostingImportFile()
        let parsedFile = try harness.importService.parseFile(at: fileURL)

        let result = try harness.importService.commitImport(parsedFile)
        #expect(result.importedTransactionCount == 2, "Expected both parent and child category transactions to import")

        let descriptions = try harness.databaseManager.dbQueue.read { db in
            try String.fetchAll(
                db,
                sql: """
                SELECT description
                FROM transactions
                WHERE description IN ('Veronika', 'Child category tx')
                ORDER BY description
                """
            )
        }

        #expect(descriptions == ["Child category tx", "Veronika"], "Expected parent category posting not to be dropped")
    }

    @Test
    func moneydanceAccountTypesAndHierarchyImportCorrectly() throws {
        let harness = try ImportHarness()
        defer { harness.cleanup() }

        let fileURL = try harness.makeAccountHierarchyAndTypeImportFile()
        let parsedFile = try harness.importService.parseFile(at: fileURL)
        let result = try harness.importService.commitImport(parsedFile)

        let importedAccounts = try harness.databaseManager.dbQueue.read { db in
            try Account
                .order(Account.Columns.id.asc)
                .fetchAll(db)
        }

        let accountsByName = Dictionary(grouping: importedAccounts, by: \.name)

        let kpAccount = try #require(accountsByName["KP"]?.first)
        #expect(kpAccount.parentID == nil, "Expected KP root to be preserved")
        #expect(kpAccount.class == "asset", "Expected KP root to stay a real asset account")
        #expect(kpAccount.subtype == "cash", "Expected KP root family to classify as cash")

        let hufAccount = try #require(
            accountsByName["HUF"]?.first(where: { $0.parentID == kpAccount.id })
        )
        #expect(hufAccount.class == "asset", "Expected KP:HUF to stay under real accounts")
        #expect(hufAccount.subtype == "cash", "Expected KP:HUF branch to classify as cash")

        let noraCash = try #require(
            accountsByName["Nóra"]?.first(where: { $0.parentID == hufAccount.id })
        )
        #expect(noraCash.class == "asset", "Expected CASH to map to asset")
        #expect(noraCash.subtype == "cash", "Expected CASH to map to cash subtype")
        #expect(noraCash.currency == "HUF", "Expected KP:HUF:Nóra currency to stay HUF")

        let peterCash = try #require(
            accountsByName["Péter"]?.first(where: { $0.parentID == hufAccount.id })
        )
        #expect(peterCash.class == "asset", "Expected KP:HUF:Péter to stay an asset")
        #expect(peterCash.subtype == "cash", "Expected KP:HUF:Péter to stay cash")
        #expect(peterCash.currency == "HUF", "Expected KP:HUF:Péter currency to stay HUF")

        let creditAccount = try #require(accountsByName["Erste Credit"]?.first)
        #expect(creditAccount.class == "liability", "Expected CREDIT_CARD to map to liability")
        #expect(creditAccount.subtype == "credit", "Expected CREDIT_CARD to map to credit subtype")
        #expect(creditAccount.currency == "HUF", "Expected credit card currency to stay HUF")

        let otpAccount = try #require(accountsByName["OTP Class"]?.first)
        #expect(otpAccount.class == "asset", "Expected BANK to map to asset")
        #expect(otpAccount.subtype == "bank", "Expected BANK to map to bank subtype")
        #expect(otpAccount.currency == "HUF", "Expected OTP Class currency to stay HUF")

        let investmentAccount = try #require(accountsByName["Péter HUF befektetések"]?.first)
        #expect(investmentAccount.class == "asset", "Expected INVESTMENT to map to asset")
        #expect(investmentAccount.subtype == "investment", "Expected INVESTMENT to map to investment subtype")

        let stockAccount = try #require(accountsByName["Erste Stock EM Global"]?.first)
        #expect(stockAccount.class == "asset", "Expected SECURITY to map to asset")
        #expect(stockAccount.subtype == "investment", "Expected SECURITY to map to investment subtype")
        #expect(stockAccount.currency == "HUF", "Expected security currency to stay HUF")

        let liabilityAccount = try #require(accountsByName["Nóra Erste személyi kölcsön"]?.first)
        #expect(liabilityAccount.class == "liability", "Expected LIABILITY to map to liability")
        #expect(liabilityAccount.subtype == "loan", "Expected LIABILITY to map to loan subtype")
        #expect(liabilityAccount.currency == "HUF", "Expected liability currency to stay HUF")

        let incomeCategory = try #require(accountsByName["Salary"]?.first)
        #expect(incomeCategory.class == "income", "Expected INCOME to stay a category")

        let expenseCategory = try #require(accountsByName["Groceries"]?.first)
        #expect(expenseCategory.class == "expense", "Expected EXPENSE to stay a category")

        #expect(result.createdBankAccountsCount >= 1, "Expected bank accounts to be counted in import summary")
        #expect(result.createdCashAccountsCount >= 1, "Expected cash accounts to be counted in import summary")
        #expect(result.createdInvestmentAccountsCount >= 1, "Expected investment accounts to be counted in import summary")
        #expect(result.createdCreditCardAccountsCount >= 1, "Expected credit cards to be counted in import summary")
        #expect(result.createdLiabilityAccountsCount >= 1, "Expected loans/liabilities to be counted in import summary")
    }
}

private struct StatusCase {
    let name: String
    let mainStatus: String
    let continuationStatus: String
    let expectedState: String
}

private struct WarningCase {
    let name: String
    let occurrenceDate: String
    let mainStatus: String
    let continuationStatus: String
    let expectedState: String
    let expectedWarningReason: String
}

private final class ImportHarness {
    let tempDirectoryURL: URL
    let databaseManager: DatabaseManager
    let transactionRepository: TransactionRepository
    let transactionService: TransactionService
    let importService: ImportService

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

        importService = ImportService(
            databaseManager: databaseManager,
            accountRepository: accountRepository,
            transactionService: transactionService,
            transactionRepository: transactionRepository
        )
    }

    func makeImportFile(for testCase: StatusCase) throws -> URL {
        let fileURL = tempDirectoryURL.appendingPathComponent("\(UUID().uuidString).txt")
        let contents = """
        #Account\tAccount ID\tAccount Type\tCurrency\tStart Balance
        Erste:HUF:Peter Erste HUF\tcdbb206e-beb2-4bd0-9337-0f32bc0b5d31\tBANK\tHUF\t4843441
        #Date\tTax Date\tDate Entered\tCheck Number\tDescription\tStatus\tAccount\tMemo\tAmount
        2025.09.12\t2025.09.12\t2025.09.11 17:29:42:378\t\tIngatlanadó\t\(testCase.mainStatus)\tErste:HUF:Peter Erste HUF\t\t-70425
        -\t-\t-\t-\t-\t\(testCase.continuationStatus)\tAdó:Ingatlanadó\tIngatlanadó\t-70425
        """
        try contents.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    func makeDuplicateImportFile() throws -> URL {
        let fileURL = tempDirectoryURL.appendingPathComponent("\(UUID().uuidString)-duplicate.txt")
        let contents = """
        #Account\tAccount ID\tAccount Type\tCurrency\tStart Balance
        Erste:HUF:Peter Erste HUF\tcdbb206e-beb2-4bd0-9337-0f32bc0b5d31\tBANK\tHUF\t4843441
        #Date\tTax Date\tDate Entered\tCheck Number\tDescription\tStatus\tAccount\tMemo\tAmount
        2025.09.12\t2025.09.12\t2025.09.11 17:29:42:378\t\tIngatlanadó\tX\tErste:HUF:Peter Erste HUF\t\t-70425
        -\t-\t-\t-\t-\tX\tAdó:Ingatlanadó\tIngatlanadó\t-70425
        2025.09.12\t2025.09.12\t2025.09.11 17:29:42:378\t\tIngatlanadó\t\tErste:HUF:Peter Erste HUF\t\t-70425
        -\t-\t-\t-\t-\t\tAdó:Ingatlanadó\tIngatlanadó\t-70425
        """
        try contents.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    func makeMirroredCategoryImportFile() throws -> URL {
        let fileURL = tempDirectoryURL.appendingPathComponent("\(UUID().uuidString)-mirrored.txt")
        let contents = """
        #Account\tAccount ID\tAccount Type\tCurrency\tStart Balance
        Erste:HUF:Peter Erste HUF\tbank-1\tBANK\tHUF\t4843441
        Adó:Ingatlanadó\texpense-1\tEXPENSE\tHUF\t0
        #Date\tTax Date\tDate Entered\tCheck Number\tDescription\tStatus\tAccount\tMemo\tAmount
        2025.09.12\t2025.09.12\t2025.09.11 17:29:42:378\t\tIngatlanadó\tX\tErste:HUF:Peter Erste HUF\t\t-70425
        -\t-\t-\t-\t-\tX\tAdó:Ingatlanadó\tIngatlanadó\t-70425
        2025.09.12\t2025.09.12\t2025.09.11 17:29:42:378\t\tIngatlanadó\t\tAdó:Ingatlanadó\t\t70425
        -\t-\t-\t-\t-\t\tErste:HUF:Peter Erste HUF\tIngatlanadó\t70425
        """
        try contents.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    func makeMirroredTransferImportFile() throws -> URL {
        let fileURL = tempDirectoryURL.appendingPathComponent("\(UUID().uuidString)-mirrored-transfer.txt")
        let contents = """
        #Account\tAccount ID\tAccount Type\tCurrency\tStart Balance
        Erste:HUF:Peter Erste HUF\tbank-1\tBANK\tHUF\t4843441
        KP:HUF:Nóra\tcash-1\tCASH\tHUF\t0
        #Date\tTax Date\tDate Entered\tCheck Number\tDescription\tStatus\tAccount\tMemo\tAmount
        2026.02.11\t2026.02.11\t2026.02.14 11:59:24:535\t\t\tX\tErste:HUF:Peter Erste HUF\t\t-19000
        -\t-\t-\t-\t-\tX\tKP:HUF:Nóra\t\t-19000
        2026.02.11\t2026.02.11\t2026.02.14 11:59:24:535\t\t\t\tKP:HUF:Nóra\t\t19000
        -\t-\t-\t-\t-\t\tErste:HUF:Peter Erste HUF\t\t19000
        """
        try contents.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    func makeWarningImportFile(for testCase: WarningCase) throws -> URL {
        let fileURL = tempDirectoryURL.appendingPathComponent("\(UUID().uuidString)-warning.txt")
        let contents = """
        #Account\tAccount ID\tAccount Type\tCurrency\tStart Balance
        Erste:HUF:Peter Erste HUF\tcdbb206e-beb2-4bd0-9337-0f32bc0b5d31\tBANK\tHUF\t4843441
        #Date\tTax Date\tDate Entered\tCheck Number\tDescription\tStatus\tAccount\tMemo\tAmount
        \(testCase.occurrenceDate)\t\(testCase.occurrenceDate)\t2025.09.11 17:29:42:378\t\tIngatlanadó\t\(testCase.mainStatus)\tErste:HUF:Peter Erste HUF\t\t-70425
        -\t-\t-\t-\t-\t\(testCase.continuationStatus)\tAdó:Ingatlanadó\tIngatlanadó\t-70425
        """
        try contents.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    func makeOpeningBalanceImportFile() throws -> URL {
        let fileURL = tempDirectoryURL.appendingPathComponent("\(UUID().uuidString)-opening-balance.txt")
        let contents = """
        #Account\tAccount ID\tAccount Type\tCurrency\tStart Balance
        Erste:EUR:Nóra Erste EUR\t61611a8f-e0f6-4e25-b3c9-d85fdb4e0dc8\tBANK\tEUR\t504.50
        #Date\tTax Date\tDate Entered\tCheck Number\tDescription\tStatus\tAccount\tMemo\tAmount
        2025.09.12\t2025.09.12\t2025.09.11 17:29:42:378\t\tTeszt\tX\tErste:EUR:Nóra Erste EUR\t\t-10.00
        -\t-\t-\t-\t-\tX\tKöltség:Teszt\tTeszt\t-10.00
        """
        try contents.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    func makeDistinctSameDaySameAmountImportFile() throws -> URL {
        let fileURL = tempDirectoryURL.appendingPathComponent("\(UUID().uuidString)-distinct-same-day.txt")
        let contents = """
        #Account\tAccount ID\tAccount Type\tCurrency\tStart Balance
        Erste:HUF:Peter Erste HUF\tbank-1\tBANK\tHUF\t4843441
        #Date\tTax Date\tDate Entered\tCheck Number\tDescription\tStatus\tAccount\tMemo\tAmount
        2025.10.06\t2025.10.06\t2025.10.06 10:00:00:000\t\tRita zsebpénz\tX\tErste:HUF:Peter Erste HUF\t\t-10000
        -\t-\t-\t-\t-\tX\tGyerekek, oktatás:Zsebpénz\tRita zsebpénz\t-10000
        2025.10.06\t2025.10.06\t2025.10.06 10:00:00:000\t\tVeronika zsebpénz\tX\tErste:HUF:Peter Erste HUF\t\t-10000
        -\t-\t-\t-\t-\tX\tGyerekek, oktatás:Zsebpénz\tVeronika zsebpénz\t-10000
        """
        try contents.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    func makeCleanImportTransferDuplicateFile() throws -> URL {
        let fileURL = tempDirectoryURL.appendingPathComponent("\(UUID().uuidString)-clean-transfer-duplicate.txt")
        let contents = """
        #Account\tAccount ID\tAccount Type\tCurrency\tStart Balance
        KP:HUF:Nóra\tcash-1\tCASH\tHUF\t0
        Erste:HUF:Peter Erste HUF\tbank-1\tBANK\tHUF\t4843441
        #Date\tTax Date\tDate Entered\tCheck Number\tDescription\tStatus\tAccount\tMemo\tAmount
        2025.09.23\t2025.09.23\t2025.09.23 10:15:00:000\t\t-\tX\tKP:HUF:Nóra\t\t80000
        -\t-\t-\t-\t-\tX\tErste:HUF:Peter Erste HUF\t\t80000
        2025.09.23\t2025.09.23\t2025.09.23 10:15:00:000\t\t-\tX\tErste:HUF:Peter Erste HUF\t\t-80000
        -\t-\t-\t-\t-\tX\tKP:HUF:Nóra\t\t-80000
        """
        try contents.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    func makeCategoryDefinedExpenseImportFile() throws -> URL {
        let fileURL = tempDirectoryURL.appendingPathComponent("\(UUID().uuidString)-category-defined-expense.txt")
        let contents = """
        #Account\tAccount ID\tAccount Type\tCurrency\tStart Balance
        Erste:HUF:Peter Erste HUF\tbank-1\tBANK\tHUF\t4843441
        Gyerekek, oktatás\tcategory-1\tEXPENSE\tHUF\t0
        #Date\tTax Date\tDate Entered\tCheck Number\tDescription\tStatus\tAccount\tMemo\tAmount
        2025.10.17\t2025.10.17\t2025.10.17 09:00:00:000\t\tVeronika\tX\tErste:HUF:Peter Erste HUF\t\t-15000
        -\t-\t-\t-\t-\tX\tGyerekek, oktatás\tVeronika\t-15000
        """
        try contents.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    func makeCreditCardReimbursementImportFile() throws -> URL {
        let fileURL = tempDirectoryURL.appendingPathComponent("\(UUID().uuidString)-credit-card-reimbursement.txt")
        let contents = """
        #Account\tAccount ID\tAccount Type\tCurrency\tStart Balance
        Erste:HUF:Erste forintok\tbank-1\tBANK\tHUF\t0
        Erste credit\tcredit-1\tCREDIT_CARD\tHUF\t0
        #Date\tTax Date\tDate Entered\tCheck Number\tDescription\tStatus\tAccount\tMemo\tAmount
        2026.02.13\t2026.02.13\t2026.01.19 21:06:18:665\t\t\tX\tErste:HUF:Erste forintok\t\t-12048
        -\t-\t-\t-\t-\tX\tErste credit\t\t-12048
        """
        try contents.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    func makePendingCreditCardPurchaseImportFile() throws -> URL {
        let fileURL = tempDirectoryURL.appendingPathComponent("\(UUID().uuidString)-pending-credit-card-purchase.txt")
        let contents = """
        #Account\tAccount ID\tAccount Type\tCurrency\tStart Balance
        Erste credit\tcredit-1\tCREDIT_CARD\tHUF\t0
        Ház és kert:Karbantartás, javítás\texpense-1\tEXPENSE\tHUF\t0
        #Date\tTax Date\tDate Entered\tCheck Number\tDescription\tStatus\tAccount\tMemo\tAmount
        2026.03.19\t2026.03.19\t2026.03.20 20:09:43:980\t\tVillamossági szaküzlet\tx\tErste credit\t\t-6345
        -\t-\t-\t-\t-\tx\tHáz és kert:Karbantartás, javítás\tVillamossági szaküzlet\t-6345
        """
        try contents.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    func makeSharedCategoryCrossCurrencyImportFile() throws -> URL {
        let fileURL = tempDirectoryURL.appendingPathComponent("\(UUID().uuidString)-shared-category-cross-currency.txt")
        let contents = """
        #Account\tAccount ID\tAccount Type\tCurrency\tStart Balance
        Erste:HUF:Peter Erste HUF\tbank-huf\tBANK\tHUF\t0
        Erste:EUR:Peter Erste EUR\tbank-eur\tBANK\tEUR\t0
        Gyerekek, oktatás\tcategory-1\tEXPENSE\tEUR\t0
        #Date\tTax Date\tDate Entered\tCheck Number\tDescription\tStatus\tAccount\tMemo\tAmount
        2025.10.17\t2025.10.17\t2025.10.17 09:00:00:000\t\tHUF category tx\tX\tErste:HUF:Peter Erste HUF\t\t-15000
        -\t-\t-\t-\t-\tX\tGyerekek, oktatás\tHUF category tx\t-15000
        2025.10.18\t2025.10.18\t2025.10.18 09:00:00:000\t\tEUR category tx\tX\tErste:EUR:Peter Erste EUR\t\t-20
        -\t-\t-\t-\t-\tX\tGyerekek, oktatás\tEUR category tx\t-20
        """
        try contents.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    func makeParentCategoryPostingImportFile() throws -> URL {
        let fileURL = tempDirectoryURL.appendingPathComponent("\(UUID().uuidString)-parent-category-posting.txt")
        let contents = """
        #Account\tAccount ID\tAccount Type\tCurrency\tStart Balance
        Erste:HUF:Peter Erste HUF\tbank-1\tBANK\tHUF\t0
        Gyerekek, oktatás\tcategory-parent\tEXPENSE\tHUF\t0
        Gyerekek, oktatás:Tankönyv\tcategory-child\tEXPENSE\tHUF\t0
        #Date\tTax Date\tDate Entered\tCheck Number\tDescription\tStatus\tAccount\tMemo\tAmount
        2025.10.17\t2025.10.17\t2025.10.17 09:00:00:000\t\tVeronika\tX\tErste:HUF:Peter Erste HUF\t\t-15000
        -\t-\t-\t-\t-\tX\tGyerekek, oktatás\tVeronika\t-15000
        2025.10.18\t2025.10.18\t2025.10.18 09:00:00:000\t\tChild category tx\tX\tErste:HUF:Peter Erste HUF\t\t-5000
        -\t-\t-\t-\t-\tX\tGyerekek, oktatás:Tankönyv\tChild category tx\t-5000
        """
        try contents.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    func makeAccountHierarchyAndTypeImportFile() throws -> URL {
        let fileURL = tempDirectoryURL.appendingPathComponent("\(UUID().uuidString)-account-hierarchy-types.txt")
        let contents = """
        #Account\tAccount ID\tAccount Type\tCurrency\tStart Balance
        KP:HUF:Nóra\tcash-1\tCASH\tHUF\t0
        KP:HUF:Péter\tcash-2\tCASH\tHUF\t0
        KP:EUR\tcash-3\tCASH\tEUR\t0
        Erste Credit\tcredit-1\tCREDIT_CARD\tHUF\t0
        OTP Class\tbank-1\tBANK\tHUF\t0
        Péter HUF befektetések\tinvest-1\tINVESTMENT\tHUF\t0
        Erste Stock EM Global\tsecurity-1\tSECURITY\tHUF\t0
        Nóra Erste személyi kölcsön\tloan-1\tLIABILITY\tHUF\t0
        Salary\tincome-1\tINCOME\tHUF\t0
        Groceries\texpense-1\tEXPENSE\tHUF\t0
        #Date\tTax Date\tDate Entered\tCheck Number\tDescription\tStatus\tAccount\tMemo\tAmount
        2025.09.12\t2025.09.12\t2025.09.12 10:00:00:000\t\tSeed cash\tX\tKP:HUF:Nóra\t\t-1
        -\t-\t-\t-\t-\tX\tGroceries\tSeed cash\t-1
        """
        try contents.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    func seedExistingTransaction() throws {
        let accountRepository = AccountRepository(databaseManager: databaseManager)
        var sourceAccount = Account(
            name: "Seed Bank",
            class: "asset",
            subtype: "bank",
            currency: "HUF",
            isGroup: false,
            includeInNetWorth: true
        )
        try accountRepository.createAccount(&sourceAccount)

        var categoryAccount = Account(
            name: "Seed Expense",
            class: "expense",
            subtype: "group",
            currency: "HUF",
            isGroup: false,
            includeInNetWorth: false
        )
        try accountRepository.createAccount(&categoryAccount)

        try transactionService.createTransaction(
            txnDate: "2025-01-01",
            description: "Seed transaction",
            state: "cleared",
            entries: [
                EntryInput(
                    accountID: sourceAccount.id!,
                    amount: -1,
                    currency: "HUF"
                ),
                EntryInput(
                    accountID: categoryAccount.id!,
                    amount: 1,
                    currency: "HUF"
                )
            ]
        )
    }

    func cleanup() {
        try? databaseManager.close()
        try? FileManager.default.removeItem(at: tempDirectoryURL)
    }
}

private func farFutureDateToken() -> String {
    let calendar = Calendar(identifier: .gregorian)
    let futureDate = calendar.date(byAdding: .day, value: 30, to: Date()) ?? Date()
    let formatter = DateFormatter()
    formatter.calendar = calendar
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy.MM.dd"
    return formatter.string(from: futureDate)
}
