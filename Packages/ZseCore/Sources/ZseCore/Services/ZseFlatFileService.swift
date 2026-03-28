import AppKit
import Foundation
import GRDB

enum ManualImportFormat: String, CaseIterable, Identifiable {
    case moneydance
    case zse

    var id: String { rawValue }

    var title: String {
        switch self {
        case .moneydance:
            return "Moneydance"
        case .zse:
            return "zse"
        }
    }
}

enum FlatFileDelimiterOption: String, CaseIterable, Identifiable {
    case tab
    case semicolon

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tab:
            return "Tab"
        case .semicolon:
            return ";"
        }
    }

    var delimiter: Character {
        switch self {
        case .tab:
            return "\t"
        case .semicolon:
            return ";"
        }
    }
}

enum FlatFileDateFormatOption: String, CaseIterable, Identifiable {
    case yyyyDashMmDashDd
    case yyyyDotMmDotDd

    var id: String { rawValue }

    var title: String {
        switch self {
        case .yyyyDashMmDashDd:
            return "YYYY-MM-DD"
        case .yyyyDotMmDotDd:
            return "YYYY.MM.DD"
        }
    }

    func format(dateString: String) -> String {
        switch self {
        case .yyyyDashMmDashDd:
            return dateString
        case .yyyyDotMmDotDd:
            return dateString.replacingOccurrences(of: "-", with: ".")
        }
    }

    func normalizeForImport(_ token: String) -> String {
        switch self {
        case .yyyyDashMmDashDd:
            return token
        case .yyyyDotMmDotDd:
            return token.replacingOccurrences(of: ".", with: "-")
        }
    }
}

enum FlatFileDecimalSeparatorOption: String, CaseIterable, Identifiable {
    case comma
    case dot

    var id: String { rawValue }

    var title: String {
        switch self {
        case .comma:
            return ","
        case .dot:
            return "."
        }
    }

    var character: Character {
        switch self {
        case .comma:
            return ","
        case .dot:
            return "."
        }
    }
}

enum FlatFileExtensionOption: String, CaseIterable, Identifiable {
    case txt
    case csv

    var id: String { rawValue }

    var title: String { rawValue }
}

struct ZseFlatFileOptions: Equatable {
    var delimiter: FlatFileDelimiterOption = .tab
    var dateFormat: FlatFileDateFormatOption = .yyyyDashMmDashDd
    var decimalSeparator: FlatFileDecimalSeparatorOption = .comma
    var fileExtension: FlatFileExtensionOption = .txt
}

struct ZseFlatExportSummary {
    let exportedTransactionCount: Int
    let scopeDescription: String
    let destinationURL: URL
}

private struct ZseFlatExportRow {
    let date: String
    let status: String
    let type: String
    let accountPath: String
    let counterpartPath: String
    let categoryPath: String
    let description: String
    let memo: String
    let amount: Double
    let currency: String
    let accountOpeningBalance: Double?
    let counterpartAmount: Double?
    let counterpartCurrency: String?
    let counterpartOpeningBalance: Double?
    let accountClass: String
    let accountSubtype: String
    let counterpartClass: String?
    let counterpartSubtype: String?
}

private struct ZseFlatAccountRow {
    let accountPath: String
    let currency: String
    let accountOpeningBalance: Double?
    let accountClass: String
    let accountSubtype: String
}

struct ZseFlatFileService {
    private let databaseManager: DatabaseManager
    private let accountRepository: AccountRepository
    private let transactionRepository: TransactionRepository

    init(
        databaseManager: DatabaseManager,
        accountRepository: AccountRepository,
        transactionRepository: TransactionRepository
    ) {
        self.databaseManager = databaseManager
        self.accountRepository = accountRepository
        self.transactionRepository = transactionRepository
    }

    func defaultExportURL(
        scope: ExportScope,
        selectedAccount: Account?,
        options: ZseFlatFileOptions
    ) -> URL {
        let baseName: String
        switch scope {
        case .full:
            baseName = "zse_transactions"
        case .selectedAccount:
            baseName = selectedAccount.map { sanitizeFilename($0.name) } ?? "zse_selected_account"
        }

        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("\(baseName).\(options.fileExtension.rawValue)")
    }

    func exportTransactions(
        scope: ExportScope,
        selectedAccountID: Int64?,
        destinationURL: URL,
        options: ZseFlatFileOptions
    ) throws -> ZseFlatExportSummary {
        let effectiveSelectedAccountID = scope == .selectedAccount ? selectedAccountID : nil
        let rows = try buildExportRows(selectedAccountID: effectiveSelectedAccountID)
        let accountRows = try buildAccountRows(selectedAccountID: effectiveSelectedAccountID)
        let contents = makeFileContents(rows: rows, accountRows: accountRows, options: options)
        try contents.write(to: destinationURL, atomically: true, encoding: .utf8)

        return ZseFlatExportSummary(
            exportedTransactionCount: rows.count,
            scopeDescription: scope.title,
            destinationURL: destinationURL
        )
    }

    private func buildExportRows(selectedAccountID: Int64?) throws -> [ZseFlatExportRow] {
        let accounts = try accountRepository.getAllAccounts()
        let accountsByID = Dictionary(uniqueKeysWithValues: accounts.compactMap { account -> (Int64, Account)? in
            guard let accountID = account.id else { return nil }
            return (accountID, account)
        })
        let pathByID = Dictionary(uniqueKeysWithValues: accounts.compactMap { account -> (Int64, String)? in
            guard let accountID = account.id else { return nil }
            return (accountID, buildAccountPath(for: account, accountsByID: accountsByID))
        })

        let transactions = try transactionRepository.fetchTransactions()
        var rows: [ZseFlatExportRow] = []

        for transaction in transactions.sorted(by: { ($0.txnDate, $0.id ?? 0) < ($1.txnDate, $1.id ?? 0) }) {
            guard let transactionID = transaction.id,
                  let detail = try transactionRepository.fetchTransactionDetail(transactionID: transactionID) else {
                continue
            }

            let entryAccountIDs = Set(detail.entries.map(\.accountID))
            if let selectedAccountID, !entryAccountIDs.contains(selectedAccountID) {
                continue
            }

            if let row = makeExportRow(
                detail: detail,
                selectedAccountID: selectedAccountID,
                accountsByID: accountsByID,
                pathByID: pathByID
            ) {
                rows.append(row)
            }
        }

        return rows
    }

    private func buildAccountRows(selectedAccountID: Int64?) throws -> [ZseFlatAccountRow] {
        let accounts = try accountRepository.getAllAccounts()
        let accountsByID = Dictionary(uniqueKeysWithValues: accounts.compactMap { account -> (Int64, Account)? in
            guard let accountID = account.id else { return nil }
            return (accountID, account)
        })
        let pathByID = Dictionary(uniqueKeysWithValues: accounts.compactMap { account -> (Int64, String)? in
            guard let accountID = account.id else { return nil }
            return (accountID, buildAccountPath(for: account, accountsByID: accountsByID))
        })

        let selectedPrefix: String? = selectedAccountID.flatMap { pathByID[$0] }

        return accounts.compactMap { account in
            guard let accountID = account.id, let path = pathByID[accountID] else {
                return nil
            }

            if let selectedPrefix,
               path != selectedPrefix,
               !path.hasPrefix(selectedPrefix + ":") {
                return nil
            }

            return ZseFlatAccountRow(
                accountPath: path,
                currency: account.currency,
                accountOpeningBalance: account.openingBalance,
                accountClass: account.class,
                accountSubtype: account.subtype
            )
        }
        .sorted { $0.accountPath.localizedCaseInsensitiveCompare($1.accountPath) == .orderedAscending }
    }

    private func makeExportRow(
        detail: TransactionDetail,
        selectedAccountID: Int64?,
        accountsByID: [Int64: Account],
        pathByID: [Int64: String]
    ) -> ZseFlatExportRow? {
        let visibleEntries = detail.entries.filter { !($0.isStructural) }
        guard visibleEntries.count == 2 else {
            return nil
        }

        let populatedMemo = visibleEntries.compactMap(\.memo).first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) ?? ""
        let status = displayStatus(detail.state)

        guard
            let firstAccount = accountsByID[visibleEntries[0].accountID],
            let secondAccount = accountsByID[visibleEntries[1].accountID],
            let firstPath = pathByID[visibleEntries[0].accountID],
            let secondPath = pathByID[visibleEntries[1].accountID]
        else {
            return nil
        }

        let firstIsCategory = isCategoryClass(firstAccount.class)
        let secondIsCategory = isCategoryClass(secondAccount.class)

        if firstIsCategory != secondIsCategory {
            let categoryEntry = firstIsCategory ? visibleEntries[0] : visibleEntries[1]
            let categoryAccount = firstIsCategory ? firstAccount : secondAccount
            let categoryPath = firstIsCategory ? firstPath : secondPath
            let realEntry = firstIsCategory ? visibleEntries[1] : visibleEntries[0]
            let realAccount = firstIsCategory ? secondAccount : firstAccount
            let realPath = firstIsCategory ? secondPath : firstPath

            return ZseFlatExportRow(
                date: detail.txnDate,
                status: status,
                type: categoryAccount.class == "income" ? "income" : "expense",
                accountPath: realPath,
                counterpartPath: "",
                categoryPath: categoryPath,
                description: detail.description ?? "",
                memo: populatedMemo,
                amount: realEntry.amount,
                currency: realEntry.currency,
                accountOpeningBalance: realAccount.openingBalance,
                counterpartAmount: nil,
                counterpartCurrency: nil,
                counterpartOpeningBalance: nil,
                accountClass: realAccount.class,
                accountSubtype: realAccount.subtype,
                counterpartClass: nil,
                counterpartSubtype: nil
            )
        }

        let chosenEntries: (TransactionDetailEntry, TransactionDetailEntry, Account, Account, String, String)
        if let selectedAccountID,
           let selectedEntry = visibleEntries.first(where: { $0.accountID == selectedAccountID }),
           let counterpartEntry = visibleEntries.first(where: { $0.accountID != selectedAccountID }),
           let selectedAccount = accountsByID[selectedEntry.accountID],
           let counterpartAccount = accountsByID[counterpartEntry.accountID],
           let selectedPath = pathByID[selectedEntry.accountID],
           let counterpartPath = pathByID[counterpartEntry.accountID] {
            chosenEntries = (selectedEntry, counterpartEntry, selectedAccount, counterpartAccount, selectedPath, counterpartPath)
        } else if visibleEntries[0].amount < 0 {
            chosenEntries = (visibleEntries[0], visibleEntries[1], firstAccount, secondAccount, firstPath, secondPath)
        } else {
            chosenEntries = (visibleEntries[1], visibleEntries[0], secondAccount, firstAccount, secondPath, firstPath)
        }

        let (accountEntry, counterpartEntry, account, counterpartAccount, accountPath, counterpartPath) = chosenEntries
        let transferType = accountEntry.currency == counterpartEntry.currency
            ? "transfer_same_currency"
            : "transfer_cross_currency"

        return ZseFlatExportRow(
            date: detail.txnDate,
            status: status,
            type: transferType,
            accountPath: accountPath,
            counterpartPath: counterpartPath,
            categoryPath: "",
            description: detail.description ?? "",
            memo: populatedMemo,
            amount: accountEntry.amount,
            currency: accountEntry.currency,
            accountOpeningBalance: account.openingBalance,
            counterpartAmount: counterpartEntry.amount,
            counterpartCurrency: counterpartEntry.currency,
            counterpartOpeningBalance: counterpartAccount.openingBalance,
            accountClass: account.class,
            accountSubtype: account.subtype,
            counterpartClass: counterpartAccount.class,
            counterpartSubtype: counterpartAccount.subtype
        )
    }

    private func makeFileContents(rows: [ZseFlatExportRow], accountRows: [ZseFlatAccountRow], options: ZseFlatFileOptions) -> String {
        let header = [
            "Date",
            "Status",
            "Type",
            "AccountPath",
            "CounterpartPath",
            "CategoryPath",
            "Description",
            "Memo",
            "Amount",
            "Currency",
            "AccountOpeningBalance",
            "CounterpartAmount",
            "CounterpartCurrency",
            "CounterpartOpeningBalance",
            "AccountClass",
            "AccountSubtype",
            "CounterpartClass",
            "CounterpartSubtype"
        ]

        let accountBody = accountRows.map { row in
            [
                "",
                "",
                "account",
                row.accountPath,
                "",
                "",
                "",
                "",
                "",
                row.currency,
                row.accountOpeningBalance.map { format(amount: $0, options: options) } ?? "",
                "",
                "",
                "",
                row.accountClass,
                row.accountSubtype,
                "",
                ""
            ]
            .map { escaped($0, delimiter: options.delimiter.delimiter) }
            .joined(separator: String(options.delimiter.delimiter))
        }

        let transactionBody = rows.map { row in
            [
                options.dateFormat.format(dateString: row.date),
                row.status,
                row.type,
                row.accountPath,
                row.counterpartPath,
                row.categoryPath,
                row.description,
                row.memo,
                format(amount: row.amount, options: options),
                row.currency,
                row.accountOpeningBalance.map { format(amount: $0, options: options) } ?? "",
                row.counterpartAmount.map { format(amount: $0, options: options) } ?? "",
                row.counterpartCurrency ?? "",
                row.counterpartOpeningBalance.map { format(amount: $0, options: options) } ?? "",
                row.accountClass,
                row.accountSubtype,
                row.counterpartClass ?? "",
                row.counterpartSubtype ?? ""
            ]
            .map { escaped($0, delimiter: options.delimiter.delimiter) }
            .joined(separator: String(options.delimiter.delimiter))
        }

        return ([header.map { escaped($0, delimiter: options.delimiter.delimiter) }
            .joined(separator: String(options.delimiter.delimiter))] + accountBody + transactionBody).joined(separator: "\n")
    }

    private func format(amount: Double, options: ZseFlatFileOptions) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ""
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = amount.rounded() == amount ? 0 : 2
        formatter.maximumFractionDigits = 8
        formatter.decimalSeparator = String(options.decimalSeparator.character)
        return formatter.string(from: NSNumber(value: amount)) ?? "\(amount)"
    }

    private func escaped(_ value: String, delimiter: Character) -> String {
        if value.contains(delimiter) || value.contains("\"") || value.contains("\n") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }

    private func displayStatus(_ state: String) -> String {
        switch state {
        case "reconciling":
            return "pending"
        default:
            return state
        }
    }

    private func isCategoryClass(_ accountClass: String) -> Bool {
        accountClass == "income" || accountClass == "expense"
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

    private func sanitizeFilename(_ value: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        return value.components(separatedBy: invalid).joined(separator: "_")
    }
}

enum ExportScope: String, CaseIterable, Identifiable {
    case full
    case selectedAccount

    var id: String { rawValue }

    var title: String {
        switch self {
        case .full:
            return "Full"
        case .selectedAccount:
            return "Selected account"
        }
    }
}
