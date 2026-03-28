import AppKit
import Foundation
import GRDB
import UniformTypeIdentifiers

enum ImportFileFormat: String {
    case moneydanceTab = "Moneydance TXT (tab-delimited)"
    case zseFlat = "zse flat (one row per transaction)"
}

struct ImportWarning: Identifiable {
    let id = UUID()
    let lineNumber: Int?
    let message: String
}

struct ParsedImportTransaction {
    enum Kind {
        case income
        case expense
        case sameCurrencyTransfer
        case crossCurrencyTransfer
    }

    let occurrenceDate: String
    let enteredTimestamp: String?
    let description: String?
    let memo: String?
    let state: String
    let statusWarningFlag: Bool
    let statusWarningReason: String?
    let accountPath: String
    let accountAmount: Double
    let counterpartPath: String
    let counterpartAmount: Double
    let kind: Kind
    let usedFallbackClassification: Bool
    let accountCurrency: String
    let counterpartCurrency: String
    let lineNumbers: [Int]
}

private extension ParsedImportTransaction.Kind {
    var kindKey: String {
        switch self {
        case .income:
            return "income"
        case .expense:
            return "expense"
        case .sameCurrencyTransfer:
            return "sameCurrencyTransfer"
        case .crossCurrencyTransfer:
            return "crossCurrencyTransfer"
        }
    }
}

struct ParsedImportFile {
    let format: ImportFileFormat
    let delimiter: Character
    let sourceAccountPath: String?
    let sourceAccountCurrency: String?
    let continuationRowCount: Int
    let transactions: [ParsedImportTransaction]
    let accountDefinitions: [MoneydanceAccountDefinition]
    let currencies: Set<String>
    let warnings: [ImportWarning]
    let skippedRowCount: Int
}

struct ImportPreviewSummary {
    let formatDescription: String
    let sourceAccountPath: String?
    let sourceAccountCurrency: String?
    let parsedTransactionCount: Int
    let continuationRowCount: Int
    let accountsToCreateCount: Int
    let categoriesToCreateCount: Int
    let sourceCategoryPathCount: Int
    let missingCategoryPathsCount: Int
    let incomeCount: Int
    let expenseCount: Int
    let sameCurrencyTransferCount: Int
    let crossCurrencyTransferCount: Int
    let fallbackClassificationCount: Int
    let warningsCount: Int
    let skippedRowCount: Int
}

struct ImportCommitResult {
    let importedTransactionCount: Int
    let createdAccountsCount: Int
    let createdCategoriesCount: Int
    let sourceCategoryPathCount: Int
    let missingCategoryPathsAfterImportCount: Int
    let createdBankAccountsCount: Int
    let createdCashAccountsCount: Int
    let createdInvestmentAccountsCount: Int
    let createdLiabilityAccountsCount: Int
    let createdCreditCardAccountsCount: Int
    let incomeCount: Int
    let expenseCount: Int
    let sameCurrencyTransferCount: Int
    let crossCurrencyTransferCount: Int
    let fallbackClassificationCount: Int
    let skippedRowCount: Int
    let warningsCount: Int
}

private struct CreatedAccountCounts {
    var bankAccounts = 0
    var cashAccounts = 0
    var investmentAccounts = 0
    var liabilityAccounts = 0
    var creditCardAccounts = 0

    mutating func record(accountClass: String, subtype: String) {
        switch (accountClass, subtype) {
        case ("asset", "bank"):
            bankAccounts += 1
        case ("asset", "cash"):
            cashAccounts += 1
        case ("asset", "investment"):
            investmentAccounts += 1
        case ("liability", "credit"):
            creditCardAccounts += 1
        case ("liability", _):
            liabilityAccounts += 1
        default:
            break
        }
    }
}

struct MoneydanceAccountDefinition {
    let path: String
    let type: String?
    let currency: String
    let openingBalance: Double?
}

private struct MoneydanceRawTransactionRow {
    let lineNumber: Int
    let dateToken: String
    let enteredToken: String?
    let description: String?
    let accountPath: String?
    let memo: String?
    let amountToken: String?
    let statusToken: String?
}

private struct MoneydanceRawTransactionGroup {
    let mainRow: MoneydanceRawTransactionRow
    let continuationRows: [MoneydanceRawTransactionRow]
}

@MainActor
final class ImportViewModel: ObservableObject {
    @Published private(set) var selectedFileURL: URL?
    @Published private(set) var preview: ParsedImportFile?
    @Published private(set) var previewSummary: ImportPreviewSummary?
    @Published private(set) var resultSummary: ImportCommitResult?
    @Published private(set) var isImporting = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var selectedFormat: ManualImportFormat = .moneydance
    @Published private(set) var zseOptions = ZseFlatFileOptions()

    private let importService: ImportService

    init(importService: ImportService) {
        self.importService = importService
    }

    func chooseFile(format: ManualImportFormat, zseOptions: ZseFlatFileOptions) {
        let panel = NSOpenPanel()
        panel.title = "Import Transactions"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [
            UTType.tabSeparatedText,
            UTType.commaSeparatedText,
            UTType.plainText,
            UTType.text
        ]

        guard panel.runModal() == .OK, let fileURL = panel.url else {
            return
        }

        selectedFormat = format
        self.zseOptions = zseOptions
        selectedFileURL = fileURL
        loadPreview(format: format, zseOptions: zseOptions)
    }

    func loadPreview(format: ManualImportFormat? = nil, zseOptions: ZseFlatFileOptions? = nil) {
        guard let selectedFileURL else {
            return
        }

        let effectiveFormat = format ?? selectedFormat
        let effectiveOptions = zseOptions ?? self.zseOptions
        selectedFormat = effectiveFormat
        self.zseOptions = effectiveOptions

        do {
            let parsedFile = try importService.parseFile(
                at: selectedFileURL,
                format: effectiveFormat,
                zseOptions: effectiveOptions
            )
            preview = parsedFile
            previewSummary = try importService.buildPreviewSummary(from: parsedFile)
            resultSummary = nil
            errorMessage = nil
        } catch {
            preview = nil
            previewSummary = nil
            resultSummary = nil
            errorMessage = error.localizedDescription
        }
    }

    func commitImport() throws -> ImportCommitResult {
        guard let preview else {
            throw ImportError.noPreviewLoaded
        }

        isImporting = true
        defer { isImporting = false }

        do {
            let result = try importService.commitImport(preview)
            resultSummary = result
            errorMessage = nil
            return result
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }
}

struct ImportService {
    private let databaseManager: DatabaseManager
    private let accountRepository: AccountRepository
    private let transactionService: TransactionService
    private let transactionRepository: TransactionRepository

    init(
        databaseManager: DatabaseManager,
        accountRepository: AccountRepository,
        transactionService: TransactionService,
        transactionRepository: TransactionRepository
    ) {
        self.databaseManager = databaseManager
        self.accountRepository = accountRepository
        self.transactionService = transactionService
        self.transactionRepository = transactionRepository
    }

    func parseFile(at fileURL: URL) throws -> ParsedImportFile {
        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        let delimiter = detectDelimiter(in: contents)
        let parser = MoneydanceImportParser(delimiter: delimiter)
        return try parser.parse(contents: contents)
    }

    func parseFile(
        at fileURL: URL,
        format: ManualImportFormat,
        zseOptions: ZseFlatFileOptions
    ) throws -> ParsedImportFile {
        let contents = try String(contentsOf: fileURL, encoding: .utf8)

        switch format {
        case .moneydance:
            let parser = MoneydanceImportParser(delimiter: detectDelimiter(in: contents))
            return try parser.parse(contents: contents)
        case .zse:
            let parser = ZseFlatImportParser(options: zseOptions)
            return try parser.parse(contents: contents)
        }
    }

    func buildPreviewSummary(from parsedFile: ParsedImportFile) throws -> ImportPreviewSummary {
        let existingAccounts = try accountRepository.getAllAccounts()
        let existingPaths = buildExistingAccountPathSet(existingAccounts)
        let accountPathsToCreate = buildAccountPathsToCreate(parsedFile: parsedFile, existingPaths: existingPaths)
        let categoryPathsToCreate = buildCategoryPathsToCreate(parsedFile: parsedFile, existingPaths: existingPaths)
        let sourceCategoryPaths = Set(
            parsedFile.transactions.compactMap { transaction in
                switch transaction.kind {
                case .income, .expense:
                    return transaction.counterpartPath
                case .sameCurrencyTransfer, .crossCurrencyTransfer:
                    return nil
                }
            }
        )

        return ImportPreviewSummary(
            formatDescription: parsedFile.format.rawValue,
            sourceAccountPath: parsedFile.sourceAccountPath,
            sourceAccountCurrency: parsedFile.sourceAccountCurrency,
            parsedTransactionCount: parsedFile.transactions.count,
            continuationRowCount: parsedFile.continuationRowCount,
            accountsToCreateCount: accountPathsToCreate.count,
            categoriesToCreateCount: categoryPathsToCreate.count,
            sourceCategoryPathCount: sourceCategoryPaths.count,
            missingCategoryPathsCount: sourceCategoryPaths.subtracting(existingPaths).count,
            incomeCount: parsedFile.transactions.filter { $0.kind == .income }.count,
            expenseCount: parsedFile.transactions.filter { $0.kind == .expense }.count,
            sameCurrencyTransferCount: parsedFile.transactions.filter { $0.kind == .sameCurrencyTransfer }.count,
            crossCurrencyTransferCount: parsedFile.transactions.filter { $0.kind == .crossCurrencyTransfer }.count,
            fallbackClassificationCount: parsedFile.transactions.filter(\.usedFallbackClassification).count,
            warningsCount: parsedFile.warnings.count,
            skippedRowCount: parsedFile.skippedRowCount
        )
    }

    func commitImport(_ parsedFile: ParsedImportFile) throws -> ImportCommitResult {
        try transactionRepository.writeInTransaction { db in
            let batchDeduplicatedTransactions = parsedFile.format == .moneydanceTab
                ? deduplicateImportBatchTransfers(parsedFile.transactions)
                : parsedFile.transactions
            let transactionsToImport = try shouldSuppressImportDuplicates(db: db)
                ? deduplicateParsedTransactions(batchDeduplicatedTransactions)
                : batchDeduplicatedTransactions
            let accountLeafPaths = Set(parsedFile.accountDefinitions.map(\.path))
            let accountStructuralPaths = structuralPaths(from: accountLeafPaths)
            let importedAccounts = try ensureImportedAccounts(
                parsedFile.accountDefinitions,
                structuralPaths: accountStructuralPaths,
                db: db
            )
            let importedCategoryPaths = makeDeclaredCategoryPathMap(
                definitions: parsedFile.accountDefinitions,
                pathToID: importedAccounts.pathToID
            )

            let categoryLeafPaths = Set(
                transactionsToImport.compactMap { transaction in
                    switch transaction.kind {
                    case .income, .expense:
                        return transaction.counterpartPath
                    case .sameCurrencyTransfer, .crossCurrencyTransfer:
                        return nil
                    }
                }
            )
            let categoryStructuralPaths = structuralPaths(
                from: categoryLeafPaths,
                excludingPostablePaths: categoryLeafPaths
            )
            let categoryPaths = try ensureImportedCategories(
                transactionsToImport,
                existingAccountPaths: Set(importedAccounts.pathToID.keys),
                protectedRealAccountPaths: Set(importedAccounts.pathToID.keys)
                    .subtracting(Set(importedCategoryPaths.map(\.key))),
                structuralPaths: categoryStructuralPaths,
                db: db
            )
            let accountPaths = importedAccounts.pathToID
            let categoryCounterpartPaths = importedCategoryPaths.merging(categoryPaths) { existing, _ in existing }
            let sourceCategoryPaths: Set<String> = Set(
                transactionsToImport.compactMap { transaction in
                    guard transaction.kind == .income || transaction.kind == .expense else {
                        return nil
                    }
                    return transaction.counterpartPath
                }
            )
            let directPostingCategoryAccountIDs = Set(
                transactionsToImport.compactMap { transaction -> Int64? in
                    guard transaction.kind == .income || transaction.kind == .expense else {
                        return nil
                    }
                    return categoryCounterpartPaths[transaction.counterpartPath]
                }
            )
            let nonPostableAccountIDs = try fetchNonPostableAccountIDs(db: db)
                .subtracting(directPostingCategoryAccountIDs)

            var importedTransactionCount = 0
            var incomeCount = 0
            var expenseCount = 0
            var sameCurrencyTransferCount = 0
            var crossCurrencyTransferCount = 0
            var skippedRowCount = parsedFile.skippedRowCount

            for transaction in transactionsToImport {
                let normalizedDescription = normalized(transaction.description)
                let normalizedMemo = normalized(transaction.memo)

                if accountStructuralPaths.contains(transaction.accountPath) {
                    skippedRowCount += 1
                    continue
                }

                switch transaction.kind {
                case .income:
                    guard let currentAccountID = accountPaths[transaction.accountPath] else {
                        throw ImportError.unresolvedImportPath(transaction.accountPath)
                    }
                    guard let categoryAccountID = categoryCounterpartPaths[transaction.counterpartPath] else {
                        skippedRowCount += 1
                        continue
                    }
                    guard !categoryStructuralPaths.contains(transaction.counterpartPath) else {
                        skippedRowCount += 1
                        continue
                    }
                    guard abs(transaction.accountAmount) > 0.000001 else {
                        skippedRowCount += 1
                        continue
                    }
                    guard !nonPostableAccountIDs.contains(currentAccountID),
                          !nonPostableAccountIDs.contains(categoryAccountID) else {
                        skippedRowCount += 1
                        continue
                    }

                    let currentAccount = try requireImportedAccount(id: currentAccountID, db: db)
                    let adjustedWarning = adjustedImportWarning(
                        for: transaction,
                        currentAccount: currentAccount
                    )

                    _ = try transactionService.createCategorizedPosting(
                        currentAccountID: currentAccountID,
                        categoryAccountID: categoryAccountID,
                        currentSignedAmount: transaction.accountAmount,
                        date: transaction.occurrenceDate,
                        description: normalizedDescription,
                        state: transaction.state,
                        statusWarningFlag: adjustedWarning != nil,
                        statusWarningReason: adjustedWarning,
                        partnerName: nil,
                        memo: normalizedMemo,
                        db: db
                    )
                    incomeCount += 1
                case .expense:
                    guard let currentAccountID = accountPaths[transaction.accountPath] else {
                        throw ImportError.unresolvedImportPath(transaction.accountPath)
                    }
                    guard let categoryAccountID = categoryCounterpartPaths[transaction.counterpartPath] else {
                        skippedRowCount += 1
                        continue
                    }
                    guard !categoryStructuralPaths.contains(transaction.counterpartPath) else {
                        skippedRowCount += 1
                        continue
                    }
                    guard abs(transaction.accountAmount) > 0.000001 else {
                        skippedRowCount += 1
                        continue
                    }
                    guard !nonPostableAccountIDs.contains(currentAccountID),
                          !nonPostableAccountIDs.contains(categoryAccountID) else {
                        skippedRowCount += 1
                        continue
                    }

                    let currentAccount = try requireImportedAccount(id: currentAccountID, db: db)
                    let adjustedWarning = adjustedImportWarning(
                        for: transaction,
                        currentAccount: currentAccount
                    )

                    _ = try transactionService.createCategorizedPosting(
                        currentAccountID: currentAccountID,
                        categoryAccountID: categoryAccountID,
                        currentSignedAmount: transaction.accountAmount,
                        date: transaction.occurrenceDate,
                        description: normalizedDescription,
                        state: transaction.state,
                        statusWarningFlag: adjustedWarning != nil,
                        statusWarningReason: adjustedWarning,
                        partnerName: nil,
                        memo: normalizedMemo,
                        db: db
                    )
                    expenseCount += 1
                case .sameCurrencyTransfer, .crossCurrencyTransfer:
                    guard
                        let firstAccountID = accountPaths[transaction.accountPath],
                        let secondAccountID = accountPaths[transaction.counterpartPath]
                    else {
                        throw ImportError.unresolvedImportPath(transaction.accountPath)
                    }
                    guard !accountStructuralPaths.contains(transaction.counterpartPath) else {
                        skippedRowCount += 1
                        continue
                    }
                    guard abs(transaction.accountAmount) > 0.000001,
                          abs(transaction.counterpartAmount) > 0.000001 else {
                        skippedRowCount += 1
                        continue
                    }
                    guard !nonPostableAccountIDs.contains(firstAccountID),
                          !nonPostableAccountIDs.contains(secondAccountID) else {
                        skippedRowCount += 1
                        continue
                    }

                    let currentAccount = try requireImportedAccount(id: firstAccountID, db: db)
                    let adjustedWarning = adjustedImportWarning(
                        for: transaction,
                        currentAccount: currentAccount
                    )

                    let sourceAccountID: Int64
                    let targetAccountID: Int64
                    let sourceAmount: Double
                    let targetAmount: Double

                    if transaction.accountAmount < 0 {
                        sourceAccountID = firstAccountID
                        targetAccountID = secondAccountID
                        sourceAmount = abs(transaction.accountAmount)
                        targetAmount = abs(transaction.counterpartAmount)
                    } else {
                        sourceAccountID = secondAccountID
                        targetAccountID = firstAccountID
                        sourceAmount = abs(transaction.counterpartAmount)
                        targetAmount = abs(transaction.accountAmount)
                    }

                    _ = try transactionService.createTransfer(
                        sourceAccountID: sourceAccountID,
                        targetAccountID: targetAccountID,
                        sourceAmount: sourceAmount,
                        targetAmount: transaction.kind == .sameCurrencyTransfer ? sourceAmount : targetAmount,
                        date: transaction.occurrenceDate,
                        description: normalizedDescription,
                        state: transaction.state,
                        statusWarningFlag: adjustedWarning != nil,
                        statusWarningReason: adjustedWarning,
                        partnerName: nil,
                        memo: normalizedMemo,
                        db: db
                    )

                    if transaction.kind == .sameCurrencyTransfer {
                        sameCurrencyTransferCount += 1
                    } else {
                        crossCurrencyTransferCount += 1
                    }
                }

                importedTransactionCount += 1
            }

            return ImportCommitResult(
                importedTransactionCount: importedTransactionCount,
                createdAccountsCount: importedAccounts.createdCount,
                createdCategoriesCount: categoryPaths.count,
                sourceCategoryPathCount: sourceCategoryPaths.count,
                missingCategoryPathsAfterImportCount: sourceCategoryPaths.subtracting(Set(categoryCounterpartPaths.keys)).count,
                createdBankAccountsCount: importedAccounts.counts.bankAccounts,
                createdCashAccountsCount: importedAccounts.counts.cashAccounts,
                createdInvestmentAccountsCount: importedAccounts.counts.investmentAccounts,
                createdLiabilityAccountsCount: importedAccounts.counts.liabilityAccounts,
                createdCreditCardAccountsCount: importedAccounts.counts.creditCardAccounts,
                incomeCount: incomeCount,
                expenseCount: expenseCount,
                sameCurrencyTransferCount: sameCurrencyTransferCount,
                crossCurrencyTransferCount: crossCurrencyTransferCount,
                fallbackClassificationCount: transactionsToImport.filter(\.usedFallbackClassification).count,
                skippedRowCount: skippedRowCount,
                warningsCount: parsedFile.warnings.count
            )
        }
    }

    private func shouldSuppressImportDuplicates(db: Database) throws -> Bool {
        try Transaction.fetchCount(db) > 0
    }

    private func detectDelimiter(in contents: String) -> Character {
        let firstInterestingLine = contents
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        if firstInterestingLine?.contains("\t") == true {
            return "\t"
        }

        return ","
    }

    private func buildExistingAccountPathSet(_ accounts: [Account]) -> Set<String> {
        let accountsByID = Dictionary(uniqueKeysWithValues: accounts.compactMap { account -> (Int64, Account)? in
            guard let accountID = account.id else { return nil }
            return (accountID, account)
        })

        return Set(accounts.compactMap { account in
            guard account.id != nil else { return nil }
            return buildAccountPath(for: account, accountsByID: accountsByID)
        })
    }

    private func buildAccountPath(for account: Account, accountsByID: [Int64: Account]) -> String {
        var components = [account.name]
        var currentParentID = account.parentID

        while let parentID = currentParentID, let parent = accountsByID[parentID] {
            components.append(parent.name)
            currentParentID = parent.parentID
        }

        return components.reversed().joined(separator: ":")
    }

    private func buildAccountPathsToCreate(parsedFile: ParsedImportFile, existingPaths: Set<String>) -> Set<String> {
        var paths = Set<String>()

        for definition in parsedFile.accountDefinitions {
            var currentPath = ""
            for component in definition.path.split(separator: ":").map(String.init) {
                currentPath = currentPath.isEmpty ? component : "\(currentPath):\(component)"
                if !existingPaths.contains(currentPath) {
                    paths.insert(currentPath)
                }
            }
        }

        return paths
    }

    private func buildCategoryPathsToCreate(parsedFile: ParsedImportFile, existingPaths: Set<String>) -> Set<String> {
        var paths = Set<String>()
        let knownAccountPaths = Set(parsedFile.accountDefinitions.map(\.path)).union(existingPaths)

        for transaction in parsedFile.transactions where !knownAccountPaths.contains(transaction.counterpartPath) {
            var currentPath = ""
            for component in transaction.counterpartPath.split(separator: ":").map(String.init) {
                currentPath = currentPath.isEmpty ? component : "\(currentPath):\(component)"
                if !existingPaths.contains(currentPath) {
                    paths.insert(currentPath)
                }
            }
        }

        return paths
    }

    private func ensureImportedAccounts(
        _ definitions: [MoneydanceAccountDefinition],
        structuralPaths: Set<String>,
        db: Database
    ) throws -> (pathToID: [String: Int64], createdCount: Int, counts: CreatedAccountCounts) {
        var pathToID = try fetchAccountPathMap(db: db)
        let definitionsByPath = Dictionary(uniqueKeysWithValues: definitions.map { ($0.path, $0) })
        var createdCount = 0
        var createdCounts = CreatedAccountCounts()

        for definition in definitions.sorted(by: { $0.path.split(separator: ":").count < $1.path.split(separator: ":").count }) {
            let components = definition.path.split(separator: ":").map(String.init)
            var currentPath = ""
            var currentParentID: Int64?

            for index in components.indices {
                let component = components[index]
                currentPath = currentPath.isEmpty ? component : "\(currentPath):\(component)"
                let isLeaf = index == components.indices.last && !structuralPaths.contains(currentPath)
                let expectedAccount = makeImportedAccount(
                    name: component,
                    parentID: currentParentID,
                    fullPath: currentPath,
                    rootPath: definition.path,
                    leafDefinition: definitionsByPath[definition.path] ?? definition,
                    isLeaf: isLeaf
                )

                if let existingID = pathToID[currentPath] {
                    try ensureImportedAccountClassification(
                        accountID: existingID,
                        expectedAccount: expectedAccount,
                        parentID: currentParentID,
                        db: db
                    )
                    currentParentID = existingID
                    continue
                }

                var createdAccount = expectedAccount
                try accountRepository.createAccount(&createdAccount, db: db)
                guard let createdID = createdAccount.id else {
                    throw ImportError.failedToCreateAccount(currentPath)
                }
                pathToID[currentPath] = createdID
                currentParentID = createdID
                createdCount += 1
                createdCounts.record(accountClass: createdAccount.class, subtype: createdAccount.subtype)
            }
        }

        return (pathToID, createdCount, createdCounts)
    }

    private func ensureImportedAccountClassification(
        accountID: Int64,
        expectedAccount: Account,
        parentID: Int64?,
        db: Database
    ) throws {
        guard var account = try accountRepository.getAccount(id: accountID, db: db) else {
            return
        }

        guard
            account.parentID != parentID ||
            account.class != expectedAccount.class ||
            account.subtype != expectedAccount.subtype ||
            account.currency != expectedAccount.currency ||
            account.isGroup != expectedAccount.isGroup ||
            account.includeInNetWorth != expectedAccount.includeInNetWorth ||
            account.openingBalance != expectedAccount.openingBalance ||
            account.openingBalanceDate != expectedAccount.openingBalanceDate
        else {
            return
        }

        account.parentID = parentID
        account.class = expectedAccount.class
        account.subtype = expectedAccount.subtype
        account.currency = expectedAccount.currency
        account.isGroup = expectedAccount.isGroup
        account.includeInNetWorth = expectedAccount.includeInNetWorth
        account.openingBalance = expectedAccount.openingBalance
        account.openingBalanceDate = expectedAccount.openingBalanceDate
        account.updatedAt = Account.makeTimestamp()
        try account.update(db)
    }

    private func ensureImportedCategories(
        _ transactions: [ParsedImportTransaction],
        existingAccountPaths: Set<String>,
        protectedRealAccountPaths: Set<String>,
        structuralPaths: Set<String>,
        db: Database
    ) throws -> [String: Int64] {
        var pathToID = try fetchAccountPathMap(db: db)

        for transaction in transactions {
            guard transaction.kind == .income || transaction.kind == .expense else {
                continue
            }

            let categoryClass = transaction.kind == .income ? "income" : "expense"
            let components = transaction.counterpartPath.split(separator: ":").map(String.init)
            var currentPath = ""
            var currentParentID: Int64?

            for index in components.indices {
                let component = components[index]
                currentPath = currentPath.isEmpty ? component : "\(currentPath):\(component)"

                if let existingID = pathToID[currentPath] {
                    if protectedRealAccountPaths.contains(currentPath) {
                        currentParentID = existingID
                        continue
                    }
                    try ensureCategoryAccountClassification(
                        accountID: existingID,
                        categoryClass: categoryClass,
                        currency: transaction.accountCurrency,
                        isDirectPostingPath: index == components.indices.last,
                        db: db
                    )
                    currentParentID = existingID
                    continue
                }

                let isLeaf = index == components.indices.last && !structuralPaths.contains(currentPath)
                var categoryAccount = Account(
                    parentID: currentParentID,
                    name: component,
                    class: categoryClass,
                    subtype: "group",
                    currency: transaction.accountCurrency,
                    isGroup: !isLeaf,
                    includeInNetWorth: false
                )
                try accountRepository.createAccount(&categoryAccount, db: db)
                guard let createdID = categoryAccount.id else {
                    throw ImportError.failedToCreateAccount(currentPath)
                }
                pathToID[currentPath] = createdID
                currentParentID = createdID
            }
        }

        return pathToID.filter { !existingAccountPaths.contains($0.key) }
    }

    private func makeDeclaredCategoryPathMap(
        definitions: [MoneydanceAccountDefinition],
        pathToID: [String: Int64]
    ) -> [String: Int64] {
        let categoryPaths = makeDeclaredCategoryPaths(from: definitions)

        return pathToID.filter { categoryPaths.contains($0.key) }
    }

    private func makeDeclaredCategoryPaths(
        from accountDefinitions: [MoneydanceAccountDefinition]
    ) -> Set<String> {
        Set(
            accountDefinitions.compactMap { definition in
                isDeclaredCategoryDefinition(definition) ? definition.path : nil
            }
        )
    }

    private func makeDeclaredCategoryClassByPath(
        from accountDefinitions: [MoneydanceAccountDefinition]
    ) -> [String: String] {
        Dictionary(
            uniqueKeysWithValues: accountDefinitions.compactMap { definition in
                let normalizedType = definition.type?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .uppercased()
                    .replacingOccurrences(of: " ", with: "_")
                    .replacingOccurrences(of: "-", with: "_") ?? ""

                switch normalizedType {
                case "INCOME":
                    return (definition.path, "income")
                case "EXPENSE":
                    return (definition.path, "expense")
                default:
                    return nil
                }
            }
        )
    }

    private func resolveDeclaredCategoryClass(
        for path: String,
        declaredCategoryClassByPath: [String: String]
    ) -> String? {
        var components = path.split(separator: ":").map(String.init)

        while !components.isEmpty {
            let candidate = components.joined(separator: ":")
            if let categoryClass = declaredCategoryClassByPath[candidate] {
                return categoryClass
            }
            _ = components.popLast()
        }

        return nil
    }

    private func isDeclaredCategoryDefinition(_ definition: MoneydanceAccountDefinition) -> Bool {
        let normalizedType = definition.type?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased() ?? ""

        return normalizedType == "INCOME" || normalizedType == "EXPENSE"
    }

    private func ensureCategoryAccountClassification(
        accountID: Int64,
        categoryClass: String,
        currency: String,
        isDirectPostingPath: Bool,
        db: Database
    ) throws {
        guard var account = try accountRepository.getAccount(id: accountID, db: db) else {
            return
        }

        guard
            account.class != categoryClass ||
            account.includeInNetWorth ||
            account.subtype != "group" ||
            account.currency != currency ||
            (isDirectPostingPath && account.isGroup)
        else {
            return
        }

        account.class = categoryClass
        account.subtype = "group"
        account.includeInNetWorth = false
        account.currency = currency
        if isDirectPostingPath {
            account.isGroup = false
        }
        account.updatedAt = Account.makeTimestamp()
        try account.update(db)
    }

    private func fetchAccountPathMap(db: Database) throws -> [String: Int64] {
        let accounts = try accountRepository.getAllAccounts(db: db)
        let accountsByID = Dictionary(uniqueKeysWithValues: accounts.compactMap { account -> (Int64, Account)? in
            guard let accountID = account.id else { return nil }
            return (accountID, account)
        })

        return Dictionary(uniqueKeysWithValues: accounts.compactMap { account -> (String, Int64)? in
            guard let accountID = account.id else { return nil }
            return (buildAccountPath(for: account, accountsByID: accountsByID), accountID)
        })
    }

    private func fetchNonPostableAccountIDs(db: Database) throws -> Set<Int64> {
        let accounts = try accountRepository.getAllAccounts(db: db)
        let parentIDs = Set(accounts.compactMap(\.parentID))

        return Set(accounts.compactMap { account in
            guard let accountID = account.id else {
                return nil
            }

            let isCategoryAccount = account.class == "income" || account.class == "expense"

            if account.isGroup {
                return accountID
            }

            if parentIDs.contains(accountID) && !isCategoryAccount {
                return accountID
            }

            return nil
        })
    }

    private func makeImportedAccount(
        name: String,
        parentID: Int64?,
        fullPath: String,
        rootPath: String,
        leafDefinition: MoneydanceAccountDefinition,
        isLeaf: Bool
    ) -> Account {
        let inferred = inferImportedAccountMetadata(
            rootPath: rootPath,
            fullPath: fullPath,
            type: leafDefinition.type
        )
        return Account(
            parentID: parentID,
            name: name,
            class: inferred.accountClass,
            subtype: inferred.subtype,
            currency: leafDefinition.currency,
            isGroup: !isLeaf,
            includeInNetWorth: inferred.includeInNetWorth,
            openingBalance: isLeaf ? leafDefinition.openingBalance : nil,
            openingBalanceDate: nil
        )
    }

    private func inferImportedAccountMetadata(
        rootPath: String,
        fullPath: String,
        type: String?
    ) -> (accountClass: String, subtype: String, includeInNetWorth: Bool) {
        let normalizedType = type?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "-", with: "_") ?? "BANK"
        let rootComponent = rootPath.split(separator: ":").first.map(String.init) ?? rootPath
        let fullPathLowercased = fullPath.lowercased()

        if normalizedType == "INCOME" {
            return ("income", "group", false)
        }

        if normalizedType == "EXPENSE" {
            return ("expense", "group", false)
        }

        if rootComponent == "KP" {
            return ("asset", "cash", true)
        }

        if rootComponent.localizedCaseInsensitiveContains("befektetések") ||
            fullPathLowercased.contains("befektetések") {
            return ("asset", "investment", true)
        }

        switch normalizedType {
        case "BANK", "CHECKING", "SAVINGS", "ASSET":
            return ("asset", "bank", true)
        case "CASH":
            return ("asset", "cash", true)
        case "CREDIT_CARD", "CREDIT":
            return ("liability", "credit", true)
        case "LIABILITY", "LOAN":
            return ("liability", "loan", true)
        case "INVESTMENT", "SECURITY", "STOCK", "BROKERAGE":
            return ("asset", "investment", true)
        case "PENSION", "RETIREMENT":
            return ("asset", "pension", true)
        case "RECEIVABLE":
            return ("asset", "receivable", true)
        case "CUSTODIAL":
            return ("asset", "custodial", true)
        default:
            return ("asset", "bank", true)
        }
    }

    private func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func structuralPaths(
        from leafPaths: Set<String>,
        excludingPostablePaths postablePaths: Set<String> = []
    ) -> Set<String> {
        var structuralPaths = Set<String>()

        for path in leafPaths {
            let components = path.split(separator: ":").map(String.init)
            guard components.count > 1 else {
                continue
            }

            var currentPath = ""
            for component in components.dropLast() {
                currentPath = currentPath.isEmpty ? component : "\(currentPath):\(component)"
                if !postablePaths.contains(currentPath) {
                    structuralPaths.insert(currentPath)
                }
            }
        }

        return structuralPaths
    }
}

private extension ImportService {
    func requireImportedAccount(id: Int64, db: Database) throws -> Account {
        guard let account = try Account.fetchOne(db, key: id) else {
            throw ImportError.unresolvedImportPath("account-id:\(id)")
        }

        return account
    }

    func adjustedImportWarning(
        for transaction: ParsedImportTransaction,
        currentAccount: Account
    ) -> String? {
        guard transaction.statusWarningFlag else {
            return nil
        }

        if transaction.statusWarningReason == "pending_past_date", currentAccount.class == "liability" {
            return nil
        }

        return transaction.statusWarningReason
    }

    func deduplicateImportBatchTransfers(_ transactions: [ParsedImportTransaction]) -> [ParsedImportTransaction] {
        var transactionsByKey: [String: ParsedImportTransaction] = [:]
        var orderedKeys: [String] = []
        var passthroughTransactions: [ParsedImportTransaction] = []

        for transaction in transactions {
            guard transaction.kind == .sameCurrencyTransfer || transaction.kind == .crossCurrencyTransfer else {
                passthroughTransactions.append(transaction)
                continue
            }

            let key = makeTransferDeduplicationKey(for: transaction)

            if let existing = transactionsByKey[key] {
                transactionsByKey[key] = mergeDuplicateTransactions(existing: existing, incoming: transaction)
            } else {
                transactionsByKey[key] = transaction
                orderedKeys.append(key)
            }
        }

        return passthroughTransactions + orderedKeys.compactMap { transactionsByKey[$0] }
    }

    func deduplicateParsedTransactions(_ transactions: [ParsedImportTransaction]) -> [ParsedImportTransaction] {
        var transactionsByKey: [String: ParsedImportTransaction] = [:]
        var orderedKeys: [String] = []

        for transaction in transactions {
            let key = makeDeduplicationKey(for: transaction)

            if let existing = transactionsByKey[key] {
                transactionsByKey[key] = mergeDuplicateTransactions(existing: existing, incoming: transaction)
            } else {
                transactionsByKey[key] = transaction
                orderedKeys.append(key)
            }
        }

        return orderedKeys.compactMap { transactionsByKey[$0] }
    }

    func makeDeduplicationKey(for transaction: ParsedImportTransaction) -> String {
        if transaction.kind == .sameCurrencyTransfer || transaction.kind == .crossCurrencyTransfer {
            return makeTransferDeduplicationKey(for: transaction)
        }

        return [
            transaction.occurrenceDate,
            transaction.enteredTimestamp ?? "",
            transaction.kind.kindKey,
            transaction.accountPath,
            String(transaction.accountAmount),
            transaction.counterpartPath,
            String(transaction.counterpartAmount),
            transaction.description ?? "",
            transaction.memo ?? ""
        ].joined(separator: "|")
    }

    func makeTransferDeduplicationKey(for transaction: ParsedImportTransaction) -> String {
        let pathPair = [transaction.accountPath, transaction.counterpartPath].sorted()
        let amountPair = [abs(transaction.accountAmount), abs(transaction.counterpartAmount)].sorted()

        return [
            transaction.occurrenceDate,
            transaction.enteredTimestamp ?? "",
            transaction.kind.kindKey,
            pathPair[0],
            pathPair[1],
            String(amountPair[0]),
            String(amountPair[1]),
            transaction.description ?? "",
            transaction.memo ?? ""
        ].joined(separator: "|")
    }

    func mergeDuplicateTransactions(
        existing: ParsedImportTransaction,
        incoming: ParsedImportTransaction
    ) -> ParsedImportTransaction {
        let preferred = preferredDuplicateTransaction(existing, incoming)
        let other = preferred.lineNumbers == existing.lineNumbers ? incoming : existing

        return ParsedImportTransaction(
            occurrenceDate: preferred.occurrenceDate,
            enteredTimestamp: preferred.enteredTimestamp ?? other.enteredTimestamp,
            description: preferredNonPlaceholderText(preferred.description, fallback: other.description),
            memo: preferredNonPlaceholderText(preferred.memo, fallback: other.memo),
            state: preferred.state,
            statusWarningFlag: preferred.statusWarningFlag,
            statusWarningReason: preferred.statusWarningReason,
            accountPath: preferred.accountPath,
            accountAmount: preferred.accountAmount,
            counterpartPath: preferred.counterpartPath,
            counterpartAmount: preferred.counterpartAmount,
            kind: preferred.kind,
            usedFallbackClassification: preferred.usedFallbackClassification && other.usedFallbackClassification,
            accountCurrency: preferred.accountCurrency,
            counterpartCurrency: preferred.counterpartCurrency,
            lineNumbers: Array(Set(existing.lineNumbers + incoming.lineNumbers)).sorted()
        )
    }

    func preferredDuplicateTransaction(
        _ left: ParsedImportTransaction,
        _ right: ParsedImportTransaction
    ) -> ParsedImportTransaction {
        let leftStatePriority = moneydanceStatePriority(left.state)
        let rightStatePriority = moneydanceStatePriority(right.state)

        if leftStatePriority != rightStatePriority {
            return leftStatePriority > rightStatePriority ? left : right
        }

        if left.statusWarningFlag != right.statusWarningFlag {
            return left.statusWarningFlag ? right : left
        }

        let leftTextScore = textQualityScore(left.description) + textQualityScore(left.memo)
        let rightTextScore = textQualityScore(right.description) + textQualityScore(right.memo)

        if leftTextScore != rightTextScore {
            return leftTextScore > rightTextScore ? left : right
        }

        return left
    }

    func preferredNonPlaceholderText(_ primary: String?, fallback: String?) -> String? {
        if textQualityScore(primary) > 0 {
            return primary
        }

        return textQualityScore(fallback) > 0 ? fallback : primary ?? fallback
    }

    func textQualityScore(_ value: String?) -> Int {
        guard let normalizedValue = normalizedImportValue(value) else {
            return 0
        }

        if normalizedValue == "-" {
            return 0
        }

        return normalizedValue.count
    }

    func moneydanceStatePriority(_ state: String) -> Int {
        switch state {
        case "cleared":
            return 2
        case "reconciling":
            return 1
        default:
            return 0
        }
    }
}

private func normalizedImportValue(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

private struct ZseFlatImportParser {
    private let options: ZseFlatFileOptions

    init(options: ZseFlatFileOptions) {
        self.options = options
    }

    func parse(contents: String) throws -> ParsedImportFile {
        let lines = contents.components(separatedBy: .newlines).filter { !$0.isEmpty }
        guard let headerLine = lines.first else {
            throw ImportError.unsupportedFileFormat
        }

        let header = split(headerLine)
        var warnings: [ImportWarning] = []
        var transactions: [ParsedImportTransaction] = []
        var definitionsByPath: [String: MoneydanceAccountDefinition] = [:]
        var currencies = Set<String>()
        var skippedRowCount = 0

        for (index, line) in lines.dropFirst().enumerated() {
            let lineNumber = index + 2
            let cells = split(line)

            do {
                let row = try parseRow(cells: cells, header: header)
                guard row.transaction != nil || !row.accountDefinitions.isEmpty else {
                    skippedRowCount += 1
                    continue
                }

                if let transaction = row.transaction {
                    transactions.append(transaction)
                }
                row.accountDefinitions.forEach { definitionsByPath[$0.path] = $0 }
                currencies.formUnion(row.accountDefinitions.map(\.currency))
                if let transaction = row.transaction {
                    currencies.insert(transaction.accountCurrency)
                    currencies.insert(transaction.counterpartCurrency)
                }
            } catch {
                warnings.append(
                    ImportWarning(
                        lineNumber: lineNumber,
                        message: error.localizedDescription
                    )
                )
                skippedRowCount += 1
            }
        }

        return ParsedImportFile(
            format: .zseFlat,
            delimiter: options.delimiter.delimiter,
            sourceAccountPath: nil,
            sourceAccountCurrency: nil,
            continuationRowCount: 0,
            transactions: transactions,
            accountDefinitions: Array(definitionsByPath.values),
            currencies: currencies,
            warnings: warnings,
            skippedRowCount: skippedRowCount
        )
    }

    private func parseRow(
        cells: [String],
        header: [String]
    ) throws -> (transaction: ParsedImportTransaction?, accountDefinitions: [MoneydanceAccountDefinition]) {
        func value(_ aliases: [String]) -> String? {
            guard let index = headerIndex(in: header, aliases: aliases), index < cells.count else {
                return nil
            }
            return normalizedImportValue(cells[index])
        }

        guard
            let rawType = value(["Type"]),
            let accountPath = value(["AccountPath"]),
            let currency = value(["Currency"])
        else {
            throw ImportError.unsupportedFileFormat
        }

        let normalizedType = rawType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let accountOpeningBalance = value(["AccountOpeningBalance"]).flatMap(parseAmount)
        let accountClass = value(["AccountClass"])
        let accountSubtype = value(["AccountSubtype"])

        let accountDefinition = MoneydanceAccountDefinition(
            path: accountPath,
            type: definitionType(forAccountClass: accountClass, subtype: accountSubtype, path: accountPath),
            currency: currency,
            openingBalance: accountOpeningBalance
        )

        if normalizedType == "account" {
            return (nil, [accountDefinition])
        }

        guard
            let rawDate = value(["Date"]),
            let rawStatus = value(["Status"]),
            let rawAmount = value(["Amount"])
        else {
            throw ImportError.unsupportedFileFormat
        }

        let date = options.dateFormat.normalizeForImport(rawDate)
        guard let amount = parseAmount(rawAmount) else {
            throw ImportError.unsupportedFileFormat
        }

        let counterpartPath = value(["CounterpartPath"]) ?? ""
        let categoryPath = value(["CategoryPath"]) ?? ""
        let counterpartAmount = value(["CounterpartAmount"]).flatMap(parseAmount)
        let counterpartCurrency = value(["CounterpartCurrency"]) ?? currency
        let counterpartOpeningBalance = value(["CounterpartOpeningBalance"]).flatMap(parseAmount)
        let counterpartClass = value(["CounterpartClass"])
        let counterpartSubtype = value(["CounterpartSubtype"])

        let state = normalizedState(rawStatus)
        let description = value(["Description"])
        let memo = value(["Memo"])
        let kind: ParsedImportTransaction.Kind
        let finalCounterpartPath: String
        let finalCounterpartAmount: Double
        let finalCounterpartCurrency: String
        var accountDefinitions: [MoneydanceAccountDefinition] = [accountDefinition]

        switch normalizedType {
        case "income":
            kind = .income
            finalCounterpartPath = categoryPath
            finalCounterpartAmount = abs(amount)
            finalCounterpartCurrency = currency
            accountDefinitions.append(
                MoneydanceAccountDefinition(
                    path: categoryPath,
                    type: "INCOME",
                    currency: currency,
                    openingBalance: nil
                )
            )
        case "expense":
            kind = .expense
            finalCounterpartPath = categoryPath
            finalCounterpartAmount = abs(amount)
            finalCounterpartCurrency = currency
            accountDefinitions.append(
                MoneydanceAccountDefinition(
                    path: categoryPath,
                    type: "EXPENSE",
                    currency: currency,
                    openingBalance: nil
                )
            )
        case "transfer_same_currency":
            kind = .sameCurrencyTransfer
            finalCounterpartPath = counterpartPath
            finalCounterpartAmount = counterpartAmount ?? -amount
            finalCounterpartCurrency = counterpartCurrency
            accountDefinitions.append(
                MoneydanceAccountDefinition(
                    path: counterpartPath,
                    type: definitionType(forAccountClass: counterpartClass, subtype: counterpartSubtype, path: counterpartPath),
                    currency: counterpartCurrency,
                    openingBalance: counterpartOpeningBalance
                )
            )
        case "transfer_cross_currency":
            kind = .crossCurrencyTransfer
            finalCounterpartPath = counterpartPath
            finalCounterpartAmount = counterpartAmount ?? -amount
            finalCounterpartCurrency = counterpartCurrency
            accountDefinitions.append(
                MoneydanceAccountDefinition(
                    path: counterpartPath,
                    type: definitionType(forAccountClass: counterpartClass, subtype: counterpartSubtype, path: counterpartPath),
                    currency: counterpartCurrency,
                    openingBalance: counterpartOpeningBalance
                )
            )
        default:
            throw ImportError.unsupportedFileFormat
        }

        return (
            ParsedImportTransaction(
                occurrenceDate: date,
                enteredTimestamp: nil,
                description: description,
                memo: memo,
                state: state,
                statusWarningFlag: false,
                statusWarningReason: nil,
                accountPath: accountPath,
                accountAmount: amount,
                counterpartPath: finalCounterpartPath,
                counterpartAmount: finalCounterpartAmount,
                kind: kind,
                usedFallbackClassification: false,
                accountCurrency: currency,
                counterpartCurrency: finalCounterpartCurrency,
                lineNumbers: []
            ),
            accountDefinitions.filter { !$0.path.isEmpty }
        )
    }

    private func split(_ line: String) -> [String] {
        var result: [String] = []
        var current = ""
        var inQuotes = false
        let delimiter = options.delimiter.delimiter
        var iterator = line.makeIterator()

        while let character = iterator.next() {
            if character == "\"" {
                if inQuotes, let next = iterator.next() {
                    if next == "\"" {
                        current.append("\"")
                    } else {
                        inQuotes = false
                        if next == delimiter {
                            result.append(current)
                            current = ""
                        } else {
                            current.append(next)
                        }
                    }
                } else {
                    inQuotes = false
                }
                continue
            }

            if character == delimiter && !inQuotes {
                result.append(current)
                current = ""
            } else {
                if character == "\"" && current.isEmpty {
                    inQuotes = true
                } else {
                    current.append(character)
                }
            }
        }

        result.append(current)
        return result
    }

    private func headerIndex(in header: [String], aliases: [String]) -> Int? {
        header.firstIndex { value in
            aliases.contains { alias in
                value.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(alias) == .orderedSame
            }
        }
    }

    private func parseAmount(_ token: String) -> Double? {
        let normalized = token.replacingOccurrences(
            of: String(options.decimalSeparator.character),
            with: "."
        )
        return Double(normalized)
    }

    private func normalizedState(_ value: String) -> String {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "pending", "reconciling":
            return "reconciling"
        case "cleared":
            return "cleared"
        default:
            return "uncleared"
        }
    }

    private func definitionType(forAccountClass accountClass: String?, subtype: String?, path: String) -> String? {
        guard let accountClass else {
            return inferredDefinitionType(from: path)
        }

        switch (accountClass, subtype ?? "") {
        case ("asset", "cash"):
            return "CASH"
        case ("asset", "investment"):
            return "INVESTMENT"
        case ("asset", "pension"):
            return "PENSION"
        case ("asset", "receivable"):
            return "RECEIVABLE"
        case ("asset", "custodial"):
            return "CUSTODIAL"
        case ("asset", _):
            return "BANK"
        case ("liability", "credit"):
            return "CREDIT_CARD"
        case ("liability", _):
            return "LIABILITY"
        case ("income", _):
            return "INCOME"
        case ("expense", _):
            return "EXPENSE"
        default:
            return inferredDefinitionType(from: path)
        }
    }

    private func inferredDefinitionType(from path: String) -> String? {
        let lowercased = path.lowercased()

        if lowercased.hasPrefix("kp") {
            return "CASH"
        }
        if lowercased.contains("befektetések") {
            return "INVESTMENT"
        }
        if lowercased.contains("credit") {
            return "CREDIT_CARD"
        }
        return "BANK"
    }
}

private struct MoneydanceImportParser {
    private enum Section {
        case none
        case currency
        case account
        case transaction
    }

    private let delimiter: Character

    init(delimiter: Character) {
        self.delimiter = delimiter
    }

    func parse(contents: String) throws -> ParsedImportFile {
        var section: Section = .none
        var currencies = Set<String>()
        var accountDefinitions: [MoneydanceAccountDefinition] = []
        var accountHeader: [String] = []
        var transactionHeader: [String] = []
        var transactionRows: [MoneydanceRawTransactionRow] = []
        var continuationRowCount = 0
        var warnings: [ImportWarning] = []
        var skippedRowCount = 0

        let lines = contents.components(separatedBy: .newlines)
        for (index, rawLine) in lines.enumerated() {
            let lineNumber = index + 1
            let line = rawLine.trimmingCharacters(in: .newlines)
            guard !line.isEmpty else { continue }

            let cells = split(line)
            guard let firstCell = cells.first else { continue }

            switch firstCell {
            case "#Currency":
                section = .currency
                continue
            case "#Account":
                section = .account
                accountHeader = cells.map(stripSectionPrefix)
                continue
            case "#Date":
                section = .transaction
                transactionHeader = cells.map(stripSectionPrefix)
                continue
            default:
                break
            }

            switch section {
            case .currency:
                if let currencyCode = cells.first?.trimmingCharacters(in: .whitespaces), !currencyCode.isEmpty {
                    currencies.insert(currencyCode)
                }
            case .account:
                if let definition = parseAccountDefinition(cells: cells, header: accountHeader) {
                    accountDefinitions.append(definition)
                    currencies.insert(definition.currency)
                } else {
                    warnings.append(ImportWarning(lineNumber: lineNumber, message: "Skipped account row with missing path or currency."))
                    skippedRowCount += 1
                }
            case .transaction:
                if let row = parseTransactionRow(cells: cells, header: transactionHeader, lineNumber: lineNumber) {
                    if row.dateToken == "-" {
                        continuationRowCount += 1
                    }
                    transactionRows.append(row)
                } else {
                    warnings.append(ImportWarning(lineNumber: lineNumber, message: "Skipped transaction row because the required fields could not be read."))
                    skippedRowCount += 1
                }
            case .none:
                warnings.append(ImportWarning(lineNumber: lineNumber, message: "Ignored line outside a supported Moneydance section."))
            }
        }

        let grouped = groupTransactions(rows: transactionRows)
        var augmentedDefinitions = accountDefinitions
        var definitionPaths = Set(accountDefinitions.map(\.path))
        let parsedTransactions = try buildParsedTransactions(
            groups: grouped,
            accountDefinitions: accountDefinitions,
            warnings: &warnings,
            skippedRowCount: &skippedRowCount
        )
        for transaction in parsedTransactions {
            for path in [transaction.accountPath, transaction.counterpartPath] {
                guard !definitionPaths.contains(path), isLikelyAccountPath(path) else {
                    continue
                }
                let currency = inferCurrency(from: path)
                augmentedDefinitions.append(
                    MoneydanceAccountDefinition(
                        path: path,
                        type: nil,
                        currency: currency,
                        openingBalance: nil
                    )
                )
                definitionPaths.insert(path)
                currencies.insert(currency)
            }
        }

        return ParsedImportFile(
            format: .moneydanceTab,
            delimiter: delimiter,
            sourceAccountPath: accountDefinitions.first?.path,
            sourceAccountCurrency: accountDefinitions.first?.currency,
            continuationRowCount: continuationRowCount,
            transactions: parsedTransactions,
            accountDefinitions: augmentedDefinitions,
            currencies: currencies,
            warnings: warnings,
            skippedRowCount: skippedRowCount
        )
    }

    private func split(_ line: String) -> [String] {
        line.split(separator: delimiter, omittingEmptySubsequences: false).map(String.init)
    }

    private func stripSectionPrefix(_ value: String) -> String {
        value.hasPrefix("#") ? String(value.dropFirst()) : value
    }

    private func parseAccountDefinition(cells: [String], header: [String]) -> MoneydanceAccountDefinition? {
        let accountIndex = headerIndex(in: header, aliases: ["Account", "Name"]) ?? 0
        let typeIndex = headerIndex(in: header, aliases: ["Type", "Account Type"])
        let currencyIndex = headerIndex(in: header, aliases: ["Currency"])
        let openingBalanceIndex = headerIndex(in: header, aliases: ["Start Balance", "Opening Balance"])

        guard accountIndex < cells.count else { return nil }
        let path = cells[accountIndex].trimmingCharacters(in: .whitespaces)
        guard !path.isEmpty else { return nil }

        let currency: String
        if let currencyIndex, currencyIndex < cells.count {
            currency = cells[currencyIndex].trimmingCharacters(in: .whitespaces)
        } else if let inferredCurrency = path.split(separator: ":").dropFirst().first {
            currency = String(inferredCurrency)
        } else {
            return nil
        }

        let type = typeIndex.flatMap { $0 < cells.count ? cells[$0] : nil }
        let openingBalance = openingBalanceIndex.flatMap { index in
            index < cells.count ? parseOptionalAmount(cells[index]) : nil
        }

        return MoneydanceAccountDefinition(
            path: path,
            type: type,
            currency: currency,
            openingBalance: openingBalance
        )
    }

    private func parseTransactionRow(cells: [String], header: [String], lineNumber: Int) -> MoneydanceRawTransactionRow? {
        guard !header.isEmpty else { return nil }

        let dateIndex = headerIndex(in: header, aliases: ["Date"]) ?? 0
        let enteredIndex = headerIndex(in: header, aliases: ["Date Entered"])
        let descriptionIndex = headerIndex(in: header, aliases: ["Description", "Description / Payee"])
        let accountIndex = headerIndex(in: header, aliases: ["Account"])
        let memoIndex = headerIndex(in: header, aliases: ["Memo", "Notes"])
        let amountIndex = headerIndex(in: header, aliases: ["Amount", "Value"])
        // Moneydance transaction exports use a fixed column order where field 6 is status.
        let statusIndex = 5

        guard dateIndex < cells.count else { return nil }

        return MoneydanceRawTransactionRow(
            lineNumber: lineNumber,
            dateToken: cells[dateIndex].trimmingCharacters(in: .whitespaces),
            enteredToken: enteredIndex.flatMap { $0 < cells.count ? cells[$0] : nil },
            description: descriptionIndex.flatMap { $0 < cells.count ? cells[$0] : nil },
            accountPath: accountIndex.flatMap { $0 < cells.count ? cells[$0] : nil },
            memo: memoIndex.flatMap { $0 < cells.count ? cells[$0] : nil },
            amountToken: amountIndex.flatMap { $0 < cells.count ? cells[$0] : nil },
            statusToken: statusIndex < cells.count ? cells[statusIndex] : nil
        )
    }

    private func headerIndex(in header: [String], aliases: [String]) -> Int? {
        header.firstIndex { value in
            aliases.contains { alias in
                value.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(alias) == .orderedSame
            }
        }
    }

    private func groupTransactions(rows: [MoneydanceRawTransactionRow]) -> [MoneydanceRawTransactionGroup] {
        var groups: [MoneydanceRawTransactionGroup] = []
        var currentMainRow: MoneydanceRawTransactionRow?
        var currentContinuations: [MoneydanceRawTransactionRow] = []

        for row in rows {
            if row.dateToken == "-" {
                if currentMainRow != nil {
                    currentContinuations.append(row)
                }
                continue
            }

            if let currentMainRow {
                groups.append(MoneydanceRawTransactionGroup(mainRow: currentMainRow, continuationRows: currentContinuations))
            }

            currentMainRow = row
            currentContinuations = []
        }

        if let currentMainRow {
            groups.append(MoneydanceRawTransactionGroup(mainRow: currentMainRow, continuationRows: currentContinuations))
        }

        return groups
    }

    private func buildParsedTransactions(
        groups: [MoneydanceRawTransactionGroup],
        accountDefinitions: [MoneydanceAccountDefinition],
        warnings: inout [ImportWarning],
        skippedRowCount: inout Int
    ) throws -> [ParsedImportTransaction] {
        let definitionByPath = Dictionary(uniqueKeysWithValues: accountDefinitions.map { ($0.path, $0) })
        let postableRealAccountPaths = makePostableRealAccountPaths(from: accountDefinitions)
        let declaredCategoryClassByPath = makeDeclaredCategoryClassByPath(from: accountDefinitions)
        var parsed: [ParsedImportTransaction] = []

        for group in groups {
            guard group.continuationRows.count == 1 else {
                warnings.append(
                    ImportWarning(
                        lineNumber: group.mainRow.lineNumber,
                        message: "Skipped transaction because Import v1 supports exactly one continuation row per transaction."
                    )
                )
                skippedRowCount += 1
                continue
            }

            let mainRow = group.mainRow
            let continuationRow = group.continuationRows[0]

            guard
                let mainPath = normalized(mainRow.accountPath),
                let counterpartPath = normalized(continuationRow.accountPath),
                let mainAmount = parseAmount(mainRow.amountToken),
                let counterpartAmount = parseAmount(continuationRow.amountToken),
                let occurrenceDate = normalizeMoneydanceDate(mainRow.dateToken)
            else {
                warnings.append(
                    ImportWarning(
                        lineNumber: group.mainRow.lineNumber,
                        message: "Skipped transaction because the required date, account, or amount fields are missing."
                    )
                )
                skippedRowCount += 1
                continue
            }

            let mainIsRealAccount = postableRealAccountPaths.contains(mainPath)
            let counterpartIsRealAccount = postableRealAccountPaths.contains(counterpartPath)
            let declaredCategoryClass = resolveDeclaredCategoryClass(
                for: counterpartPath,
                declaredCategoryClassByPath: declaredCategoryClassByPath
            )

            // Import v1 treats line 1 as the authoritative current account row.
            // Only real leaf/postable accounts may be current accounts. This skips
            // category-side mirrored exports entirely and prevents source-account /
            // memo fallbacks from turning them into bogus income rows.
            if !mainIsRealAccount {
                continue
            }

            let mainDefinition = definitionByPath[mainPath]
            let mainCurrency = mainDefinition?.currency ?? inferCurrency(from: mainPath)
            let counterpartCurrency = definitionByPath[counterpartPath]?.currency ?? inferCurrency(from: counterpartPath)

            let kind: ParsedImportTransaction.Kind
            let usedFallbackClassification: Bool
            if counterpartIsRealAccount {
                kind = mainCurrency == counterpartCurrency ? .sameCurrencyTransfer : .crossCurrencyTransfer
                usedFallbackClassification = false
            } else if declaredCategoryClass == "expense" {
                kind = .expense
                usedFallbackClassification = false
            } else if declaredCategoryClass == "income" {
                kind = .income
                usedFallbackClassification = false
            } else if mainAmount < 0 {
                kind = .expense
                usedFallbackClassification = true
            } else {
                kind = .income
                usedFallbackClassification = true
            }

            let description = normalized(mainRow.description) ?? normalized(continuationRow.description)
            let memo = normalized(mainRow.memo) ?? normalized(continuationRow.memo)
            let state = normalizedMoneydanceTransactionState(
                statusTokens: [mainRow.statusToken, continuationRow.statusToken]
            )
            let statusWarning = evaluateMoneydanceStatusWarning(
                mainStatusToken: mainRow.statusToken,
                continuationStatusToken: continuationRow.statusToken,
                resolvedState: state,
                occurrenceDate: occurrenceDate
            )

            parsed.append(
                ParsedImportTransaction(
                    occurrenceDate: occurrenceDate,
                    enteredTimestamp: normalized(mainRow.enteredToken),
                    description: description,
                    memo: memo,
                    state: state,
                    statusWarningFlag: statusWarning != nil,
                    statusWarningReason: statusWarning,
                    accountPath: mainPath,
                    accountAmount: mainAmount,
                    counterpartPath: counterpartPath,
                    counterpartAmount: counterpartAmount,
                    kind: kind,
                    usedFallbackClassification: usedFallbackClassification,
                    accountCurrency: mainCurrency,
                    counterpartCurrency: counterpartCurrency,
                    lineNumbers: [mainRow.lineNumber, continuationRow.lineNumber]
                )
            )
        }

        return parsed
    }

    private func makePostableRealAccountPaths(
        from accountDefinitions: [MoneydanceAccountDefinition]
    ) -> Set<String> {
        let realAccountPaths = Set(
            accountDefinitions.compactMap { definition in
                isRealAccountDefinition(definition) ? definition.path : nil
            }
        )
        let structuralRealAccountPaths = structuralPathsForParser(from: realAccountPaths)
        return realAccountPaths.subtracting(structuralRealAccountPaths)
    }

    private func makeDeclaredCategoryClassByPath(
        from accountDefinitions: [MoneydanceAccountDefinition]
    ) -> [String: String] {
        Dictionary(
            uniqueKeysWithValues: accountDefinitions.compactMap { definition in
                switch normalizedMoneydanceAccountType(definition.type) {
                case "INCOME":
                    return (definition.path, "income")
                case "EXPENSE":
                    return (definition.path, "expense")
                default:
                    return nil
                }
            }
        )
    }

    private func resolveDeclaredCategoryClass(
        for path: String,
        declaredCategoryClassByPath: [String: String]
    ) -> String? {
        var components = path.split(separator: ":").map(String.init)

        while !components.isEmpty {
            let candidate = components.joined(separator: ":")
            if let categoryClass = declaredCategoryClassByPath[candidate] {
                return categoryClass
            }
            _ = components.popLast()
        }

        return nil
    }

    private func isRealAccountDefinition(_ definition: MoneydanceAccountDefinition) -> Bool {
        switch normalizedMoneydanceAccountType(definition.type) {
        case "INCOME", "EXPENSE":
            return false
        case "BANK", "CHECKING", "SAVINGS", "ASSET", "CASH", "CREDIT_CARD", "CREDIT", "LIABILITY",
             "LOAN", "INVESTMENT", "SECURITY", "STOCK", "BROKERAGE", "PENSION", "RETIREMENT",
             "RECEIVABLE", "CUSTODIAL":
            return true
        default:
            return false
        }
    }

    private func structuralPathsForParser(from leafPaths: Set<String>) -> Set<String> {
        var structuralPaths = Set<String>()

        for path in leafPaths {
            let components = path.split(separator: ":").map(String.init)
            guard components.count > 1 else {
                continue
            }

            var currentPath = ""
            for component in components.dropLast() {
                currentPath = currentPath.isEmpty ? component : "\(currentPath):\(component)"
                structuralPaths.insert(currentPath)
            }
        }

        return structuralPaths
    }

    private func deduplicateParsedTransactions(_ transactions: [ParsedImportTransaction]) -> [ParsedImportTransaction] {
        var transactionsByKey: [String: ParsedImportTransaction] = [:]
        var orderedKeys: [String] = []

        for transaction in transactions {
            let key = makeDeduplicationKey(for: transaction)

            if let existing = transactionsByKey[key] {
                transactionsByKey[key] = mergeDuplicateTransactions(existing: existing, incoming: transaction)
            } else {
                transactionsByKey[key] = transaction
                orderedKeys.append(key)
            }
        }

        return orderedKeys.compactMap { transactionsByKey[$0] }
    }

    private func makeDeduplicationKey(for transaction: ParsedImportTransaction) -> String {
        if transaction.kind == .sameCurrencyTransfer || transaction.kind == .crossCurrencyTransfer {
            let pathPair = [transaction.accountPath, transaction.counterpartPath].sorted()
            let amountPair = [abs(transaction.accountAmount), abs(transaction.counterpartAmount)].sorted()

            return [
                transaction.occurrenceDate,
                transaction.kind.kindKey,
                pathPair[0],
                pathPair[1],
                String(amountPair[0]),
                String(amountPair[1])
            ].joined(separator: "|")
        }

        return [
            transaction.occurrenceDate,
            transaction.enteredTimestamp ?? "",
            transaction.kind.kindKey,
            transaction.accountPath,
            String(transaction.accountAmount),
            transaction.counterpartPath,
            String(transaction.counterpartAmount),
            transaction.description ?? "",
            transaction.memo ?? ""
        ].joined(separator: "|")
    }

    private func mergeDuplicateTransactions(
        existing: ParsedImportTransaction,
        incoming: ParsedImportTransaction
    ) -> ParsedImportTransaction {
        let preferred = preferredDuplicateTransaction(existing, incoming)
        let other = preferred.lineNumbers == existing.lineNumbers ? incoming : existing

        return ParsedImportTransaction(
            occurrenceDate: preferred.occurrenceDate,
            enteredTimestamp: preferred.enteredTimestamp ?? other.enteredTimestamp,
            description: preferredNonPlaceholderText(preferred.description, fallback: other.description),
            memo: preferredNonPlaceholderText(preferred.memo, fallback: other.memo),
            state: preferred.state,
            statusWarningFlag: preferred.statusWarningFlag,
            statusWarningReason: preferred.statusWarningReason,
            accountPath: preferred.accountPath,
            accountAmount: preferred.accountAmount,
            counterpartPath: preferred.counterpartPath,
            counterpartAmount: preferred.counterpartAmount,
            kind: preferred.kind,
            usedFallbackClassification: preferred.usedFallbackClassification && other.usedFallbackClassification,
            accountCurrency: preferred.accountCurrency,
            counterpartCurrency: preferred.counterpartCurrency,
            lineNumbers: Array(Set(existing.lineNumbers + incoming.lineNumbers)).sorted()
        )
    }

    private func preferredDuplicateTransaction(
        _ left: ParsedImportTransaction,
        _ right: ParsedImportTransaction
    ) -> ParsedImportTransaction {
        let leftStatePriority = moneydanceStatePriority(left.state)
        let rightStatePriority = moneydanceStatePriority(right.state)

        if leftStatePriority != rightStatePriority {
            return leftStatePriority > rightStatePriority ? left : right
        }

        if left.statusWarningFlag != right.statusWarningFlag {
            return left.statusWarningFlag ? right : left
        }

        let leftTextScore = textQualityScore(left.description) + textQualityScore(left.memo)
        let rightTextScore = textQualityScore(right.description) + textQualityScore(right.memo)

        if leftTextScore != rightTextScore {
            return leftTextScore > rightTextScore ? left : right
        }

        return left
    }

    private func preferredNonPlaceholderText(_ primary: String?, fallback: String?) -> String? {
        if textQualityScore(primary) > 0 {
            return primary
        }

        return textQualityScore(fallback) > 0 ? fallback : primary ?? fallback
    }

    private func textQualityScore(_ value: String?) -> Int {
        guard let normalizedValue = normalized(value) else {
            return 0
        }

        if normalizedValue == "-" {
            return 0
        }

        return normalizedValue.count
    }

    private func preferredMoneydanceState(_ left: String, _ right: String) -> String {
        moneydanceStatePriority(left) >= moneydanceStatePriority(right) ? left : right
    }

    private func moneydanceStatePriority(_ state: String) -> Int {
        switch state {
        case "cleared":
            return 2
        case "reconciling":
            return 1
        default:
            return 0
        }
    }

    private func parseAmount(_ token: String?) -> Double? {
        guard let token = normalized(token) else { return nil }
        let normalizedToken = token
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ".")
        return Double(normalizedToken)
    }

    private func parseOptionalAmount(_ token: String?) -> Double? {
        guard normalized(token) != nil else { return nil }
        return parseAmount(token)
    }

    private func normalizeMoneydanceDate(_ token: String) -> String? {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let date = Self.moneydanceDateFormatter.date(from: trimmed) {
            return Self.importDateFormatter.string(from: date)
        }

        if let date = Self.importDateFormatter.date(from: trimmed) {
            return Self.importDateFormatter.string(from: date)
        }

        return nil
    }

    private func inferCurrency(from path: String) -> String {
        let components = path.split(separator: ":").map(String.init)
        if components.count >= 2 {
            return components[1]
        }
        return "HUF"
    }

    private func normalizedMoneydanceAccountType(_ value: String?) -> String {
        value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "-", with: "_") ?? ""
    }

    private func isLikelyAccountPath(_ path: String) -> Bool {
        let components = path.split(separator: ":").map(String.init)
        guard components.count >= 3 else {
            return false
        }
        let currencyComponent = components[1]
        return currencyComponent.count == 3 && currencyComponent == currencyComponent.uppercased()
    }

    private func normalizedMoneydanceTransactionState(statusTokens: [String?]) -> String {
        let normalizedTokens = statusTokens.compactMap(normalized)

        if normalizedTokens.contains("X") {
            return "cleared"
        }

        if normalizedTokens.contains("x") {
            return "reconciling"
        }

        return "uncleared"
    }

    private func evaluateMoneydanceStatusWarning(
        mainStatusToken: String?,
        continuationStatusToken: String?,
        resolvedState: String,
        occurrenceDate: String
    ) -> String? {
        let normalizedMainStatus = normalized(mainStatusToken) ?? ""
        let normalizedContinuationStatus = normalized(continuationStatusToken) ?? ""

        if normalizedMainStatus != normalizedContinuationStatus {
            return "line_status_mismatch"
        }

        let today = Self.importDateFormatter.string(from: Date())

        if resolvedState == "cleared" && occurrenceDate > today {
            return "cleared_future_date"
        }

        if resolvedState == "reconciling" && occurrenceDate < today {
            return "pending_past_date"
        }

        if resolvedState == "uncleared" && occurrenceDate < today {
            return "uncleared_past_date"
        }

        return nil
    }

    private func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static let moneydanceDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy.MM.dd"
        return formatter
    }()

    private static let importDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

enum ImportError: Error, LocalizedError {
    case noPreviewLoaded
    case unsupportedFileFormat
    case unresolvedImportPath(String)
    case failedToCreateAccount(String)

    var errorDescription: String? {
        switch self {
        case .noPreviewLoaded:
            return "Load a file preview before importing."
        case .unsupportedFileFormat:
            return "Only Moneydance-style tab-delimited account exports are fully supported in Import v1."
        case .unresolvedImportPath(let path):
            return "The importer could not resolve the path \(path)."
        case .failedToCreateAccount(let path):
            return "The importer created \(path), but did not receive a database identifier back."
        }
    }
}
