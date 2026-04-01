import Foundation
import GRDB

struct TransactionListItem: Decodable, FetchableRecord, Identifiable {
    let transactionID: Int64
    let txnDate: String
    let createdAt: String
    let description: String?
    let partnerName: String?
    let categoryName: String?
    let memoSummary: String?
    let outAmount: Double?
    let inAmount: Double?
    let state: String
    let statusWarningFlag: Bool
    let statusWarningReason: String?
    let runningBalance: Double
    let firstEntryID: Int64
    let recurringRuleID: Int64?
    let recurringOccurrenceDate: String?

    var id: Int64 { transactionID }
    var descriptionText: String { description ?? "" }
    var partnerNameText: String { partnerName ?? "" }
    var categoryNameText: String { categoryName ?? "" }
    var memoSummaryText: String { memoSummary ?? "" }
    var outSortAmount: Double { outAmount ?? 0 }
    var inSortAmount: Double { inAmount ?? 0 }
}

private struct TransactionListRow: Decodable, FetchableRecord {
    let transactionID: Int64
    let txnDate: String
    let createdAt: String
    let description: String?
    let partnerName: String?
    let categoryName: String?
    let memoSummary: String?
    let accountAmount: Double
    let state: String
    let statusWarningFlag: Bool
    let statusWarningReason: String?
    let firstEntryID: Int64
    let recurringRuleID: Int64?
    let recurringOccurrenceDate: String?
}

struct TransactionDetail: Identifiable {
    let id: Int64
    let txnDate: String
    let description: String?
    let state: String
    let statusWarningFlag: Bool
    let statusWarningReason: String?
    let createdAt: String
    let updatedAt: String
    let partnerSummary: String?
    let memoSummary: String?
    let entries: [TransactionDetailEntry]
}

struct TransactionDetailEntry: Identifiable {
    let id: Int64
    let accountID: Int64
    let accountName: String
    let accountClass: String
    let amount: Double
    let currency: String
    let partnerName: String?
    let memo: String?
    let isStructural: Bool
}

private struct TransactionDetailRow: Decodable, FetchableRecord {
    let transactionID: Int64
    let txnDate: String
    let description: String?
    let state: String
    let statusWarningFlag: Bool
    let statusWarningReason: String?
    let createdAt: String
    let updatedAt: String
}

private struct TransactionDetailEntryRow: Decodable, FetchableRecord {
    let entryID: Int64
    let accountID: Int64
    let accountName: String
    let accountClass: String
    let amount: Double
    let currency: String
    let partnerName: String?
    let memo: String?
    let isGroup: Bool
    let hasChildren: Bool
}

struct TransactionRepository {
    private let databaseManager: DatabaseManager

    init(databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager
    }

    func createTransaction(_ transaction: inout Transaction, entries: inout [Entry]) throws {
        try databaseManager.writeInTransaction { db in
            try createTransaction(&transaction, entries: &entries, db: db)
        }
    }

    func createTransaction(_ transaction: inout Transaction, entries: inout [Entry], db: Database) throws {
        try transaction.insert(db)

        guard let transactionID = transaction.id else {
            throw PersistenceError.missingTransactionID
        }

        for index in entries.indices {
            entries[index].transactionID = transactionID
            try entries[index].insert(db)
        }
    }

    func writeInTransaction<T>(_ updates: (Database) throws -> T) throws -> T {
        try databaseManager.writeInTransaction(updates)
    }

    func updateTransaction(
        id: Int64,
        txnDate: String,
        description: String?,
        state: String
    ) throws {
        try databaseManager.writeInTransaction { db in
            try updateTransaction(
                id: id,
                txnDate: txnDate,
                description: description,
                state: state,
                db: db
            )
        }
    }

    func updateTransaction(
        id: Int64,
        txnDate: String,
        description: String?,
        state: String,
        db: Database
    ) throws {
        guard var transaction = try Transaction.fetchOne(db, key: id) else {
            throw PersistenceError.transactionNotFound(id)
        }

        transaction.txnDate = txnDate
        transaction.description = description
        transaction.state = state
        transaction.updatedAt = Self.makeTimestamp()
        try transaction.update(db)
    }

    func clearStatusWarning(transactionID: Int64, db: Database) throws {
        guard var transaction = try Transaction.fetchOne(db, key: transactionID) else {
            throw PersistenceError.transactionNotFound(transactionID)
        }

        transaction.statusWarningFlag = false
        transaction.statusWarningReason = nil
        transaction.updatedAt = Self.makeTimestamp()
        try transaction.update(db)
    }

    func updateTransaction(
        id: Int64,
        txnDate: String,
        description: String?,
        state: String,
        entries: [Entry]
    ) throws {
        try databaseManager.writeInTransaction { db in
            try updateTransaction(
                id: id,
                txnDate: txnDate,
                description: description,
                state: state,
                entries: entries,
                db: db
            )
        }
    }

    func updateTransaction(
        id: Int64,
        txnDate: String,
        description: String?,
        state: String,
        entries: [Entry],
        db: Database
    ) throws {
        try updateTransaction(
            id: id,
            txnDate: txnDate,
            description: description,
            state: state,
            db: db
        )

        for entry in entries {
            try entry.update(db)
        }
    }

    func fetchTransactions() throws -> [Transaction] {
        try databaseManager.dbQueue.read { db in
            try Transaction
                .order(Transaction.Columns.txnDate.desc, Transaction.Columns.id.desc)
                .fetchAll(db)
        }
    }

    func fetchEntries(for transactionID: Int64) throws -> [Entry] {
        try databaseManager.dbQueue.read { db in
            try fetchEntries(for: transactionID, db: db)
        }
    }

    func fetchEntries(for transactionID: Int64, db: Database) throws -> [Entry] {
        try Entry
            .filter(Entry.Columns.transactionID == transactionID)
            .order(Entry.Columns.id.asc)
            .fetchAll(db)
    }

    func deleteTransaction(id: Int64) throws {
        try databaseManager.writeInTransaction { db in
            try deleteTransaction(id: id, db: db)
        }
    }

    func deleteTransaction(id: Int64, db: Database) throws {
        _ = try Transaction.deleteOne(db, key: id)
    }

    func fetchTransactions(
        forAccountID accountID: Int64,
        performanceTrace: PerformanceTrace? = nil
    ) throws -> [TransactionListItem] {
        let sql = """
            SELECT
                transactions.id AS transactionID,
                transactions.txn_date AS txnDate,
                transactions.created_at AS createdAt,
                transactions.description AS description,
                GROUP_CONCAT(DISTINCT partners.name) AS partnerName,
                (
                    SELECT GROUP_CONCAT(counterpart_accounts.name, ', ')
                    FROM (
                        SELECT DISTINCT counterpart_accounts.name AS name
                        FROM entries AS counterpart_entries
                        INNER JOIN accounts AS counterpart_accounts ON counterpart_accounts.id = counterpart_entries.account_id
                        WHERE counterpart_entries.transaction_id = transactions.id
                          AND counterpart_entries.account_id != ?
                        ORDER BY counterpart_accounts.name
                    ) AS counterpart_accounts
                ) AS categoryName,
                GROUP_CONCAT(DISTINCT entries.memo) AS memoSummary,
                SUM(entries.amount) AS accountAmount,
                transactions.state AS state,
                transactions.status_warning_flag AS statusWarningFlag,
                transactions.status_warning_reason AS statusWarningReason,
                MIN(entries.id) AS firstEntryID,
                transactions.recurring_rule_id AS recurringRuleID,
                transactions.recurring_occurrence_date AS recurringOccurrenceDate
            FROM entries
            INNER JOIN transactions ON transactions.id = entries.transaction_id
            LEFT JOIN partners ON partners.id = entries.partner_id
            WHERE entries.account_id = ?
            GROUP BY
                transactions.id,
                transactions.txn_date,
                transactions.created_at,
                transactions.description,
                transactions.state,
                transactions.status_warning_flag,
                transactions.status_warning_reason,
                transactions.recurring_rule_id,
                transactions.recurring_occurrence_date
            ORDER BY transactions.txn_date ASC, transactions.created_at ASC, transactions.id ASC, firstEntryID ASC
            """

        return try databaseManager.dbQueue.read { db in
            let openingBalance = try Double.fetchOne(
                db,
                sql: "SELECT opening_balance FROM accounts WHERE id = ?",
                arguments: [accountID]
            ) ?? 0

            let rows = try TransactionListRow.fetchAll(db, sql: sql, arguments: [accountID, accountID])
            performanceTrace?.mark("DB fetch finished")
            var runningBalance = openingBalance
            let ascendingItems = rows.map { row in
                runningBalance += row.accountAmount

                return TransactionListItem(
                    transactionID: row.transactionID,
                    txnDate: row.txnDate,
                    createdAt: row.createdAt,
                    description: row.description,
                    partnerName: row.partnerName,
                    categoryName: row.categoryName,
                    memoSummary: row.memoSummary,
                    outAmount: row.accountAmount < 0 ? abs(row.accountAmount) : nil,
                    inAmount: row.accountAmount > 0 ? row.accountAmount : nil,
                    state: row.state,
                    statusWarningFlag: row.statusWarningFlag,
                    statusWarningReason: row.statusWarningReason,
                    runningBalance: runningBalance,
                    firstEntryID: row.firstEntryID,
                    recurringRuleID: row.recurringRuleID,
                    recurringOccurrenceDate: row.recurringOccurrenceDate
                )
            }
            performanceTrace?.mark("Running balance finished")

            return ascendingItems
        }
    }

    func fetchTransactionDetail(transactionID: Int64) throws -> TransactionDetail? {
        try databaseManager.dbQueue.read { db in
            try fetchTransactionDetail(transactionID: transactionID, db: db)
        }
    }

    func fetchTransactionDetail(transactionID: Int64, db: Database) throws -> TransactionDetail? {
        let headerSQL = """
            SELECT
                id AS transactionID,
                txn_date AS txnDate,
                description AS description,
                state AS state,
                status_warning_flag AS statusWarningFlag,
                status_warning_reason AS statusWarningReason,
                created_at AS createdAt,
                updated_at AS updatedAt
            FROM transactions
            WHERE id = ?
            """

        let entriesSQL = """
            SELECT
                entries.id AS entryID,
                accounts.id AS accountID,
                accounts.name AS accountName,
                accounts.class AS accountClass,
                entries.amount AS amount,
                entries.currency AS currency,
                partners.name AS partnerName,
                entries.memo AS memo,
                accounts.is_group AS isGroup,
                EXISTS(
                    SELECT 1
                    FROM accounts AS children
                    WHERE children.parent_id = accounts.id
                ) AS hasChildren
            FROM entries
            INNER JOIN accounts ON accounts.id = entries.account_id
            LEFT JOIN partners ON partners.id = entries.partner_id
            WHERE entries.transaction_id = ?
            ORDER BY entries.id ASC
            """

        guard let header = try TransactionDetailRow.fetchOne(
            db,
            sql: headerSQL,
            arguments: [transactionID]
        ) else {
            return nil
        }

        let entryRows = try TransactionDetailEntryRow.fetchAll(
            db,
            sql: entriesSQL,
            arguments: [transactionID]
        )

        let entries = entryRows.map { row -> TransactionDetailEntry in
            let isCategoryAccount = row.accountClass == "income" || row.accountClass == "expense"
            return TransactionDetailEntry(
                id: row.entryID,
                accountID: row.accountID,
                accountName: row.accountName,
                accountClass: row.accountClass,
                amount: row.amount,
                currency: row.currency,
                partnerName: row.partnerName,
                memo: row.memo,
                isStructural: row.isGroup || (row.hasChildren && !isCategoryAccount)
            )
        }

        let partnerSummary = summaryText(from: entryRows.compactMap(\.partnerName))
        let memoSummary = summaryText(from: entryRows.compactMap(\.memo))

        return TransactionDetail(
            id: header.transactionID,
            txnDate: header.txnDate,
            description: header.description,
            state: header.state,
            statusWarningFlag: header.statusWarningFlag,
            statusWarningReason: header.statusWarningReason,
            createdAt: header.createdAt,
            updatedAt: header.updatedAt,
            partnerSummary: partnerSummary,
            memoSummary: memoSummary,
            entries: entries
        )
    }

    func getTransactionCount() throws -> Int {
        try databaseManager.dbQueue.read { db in
            try Transaction.fetchCount(db)
        }
    }

    func hasEntries(forAccountID accountID: Int64) throws -> Bool {
        try databaseManager.dbQueue.read { db in
            try Entry
                .filter(Entry.Columns.accountID == accountID)
                .fetchCount(db) > 0
        }
    }

    private func summaryText(from values: [String]) -> String? {
        let normalizedValues = Array(
            Set(
                values
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            )
        ).sorted()

        guard !normalizedValues.isEmpty else {
            return nil
        }

        return normalizedValues.joined(separator: ", ")
    }
}

enum PersistenceError: Error, LocalizedError {
    case missingTransactionID
    case transactionNotFound(Int64)

    var errorDescription: String? {
        switch self {
        case .missingTransactionID:
            return "Transaction insert did not return a row ID."
        case .transactionNotFound(let transactionID):
            return "Transaction not found: \(transactionID)"
        }
    }
}

private extension TransactionRepository {
    static func makeTimestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }
}
