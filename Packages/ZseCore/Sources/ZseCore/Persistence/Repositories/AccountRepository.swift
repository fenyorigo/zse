import GRDB

struct AccountRepository {
    private let databaseManager: DatabaseManager

    init(databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager
    }

    func createAccount(_ account: inout Account) throws {
        account.updatedAt = account.createdAt
        try databaseManager.dbQueue.write { db in
            try account.insert(db)
        }
    }

    func createAccount(_ account: inout Account, db: Database) throws {
        account.updatedAt = account.createdAt
        try account.insert(db)
    }

    func updateAccount(_ account: Account) throws {
        try databaseManager.dbQueue.write { db in
            try account.update(db)
        }
    }

    func getAccount(id: Int64) throws -> Account? {
        try databaseManager.dbQueue.read { db in
            try getAccount(id: id, db: db)
        }
    }

    func getAccountsByParent(_ parentID: Int64?) throws -> [Account] {
        try databaseManager.dbQueue.read { db in
            let request = Account
                .filter(parentID == nil ? Account.Columns.parentID == nil : Account.Columns.parentID == parentID)
                .order(Account.Columns.sortOrder, Account.Columns.name)
            return try request.fetchAll(db)
        }
    }

    func getAllAccounts() throws -> [Account] {
        try databaseManager.dbQueue.read { db in
            try getAllAccounts(db: db)
        }
    }

    func getAccountCount() throws -> Int {
        try databaseManager.dbQueue.read { db in
            try Account.fetchCount(db)
        }
    }

    func getPostableAccounts() throws -> [Account] {
        try databaseManager.dbQueue.read { db in
            try Account
                .filter(Account.Columns.isGroup == false)
                .order(Account.Columns.sortOrder, Account.Columns.name)
                .fetchAll(db)
        }
    }

    func getLeafAccounts() throws -> [Account] {
        try databaseManager.dbQueue.read { db in
            try getLeafAccounts(db: db)
        }
    }

    func hasChildren(accountID: Int64) throws -> Bool {
        try databaseManager.dbQueue.read { db in
            try hasChildren(accountID: accountID, db: db)
        }
    }

    func deleteAccount(id: Int64) throws {
        try databaseManager.dbQueue.write { db in
            _ = try Account.deleteOne(db, key: id)
        }
    }

    func getAccountBalances() throws -> [Int64: Double] {
        struct AccountBalanceRow: Decodable, FetchableRecord {
            let accountID: Int64
            let balance: Double
        }

        let sql = """
            SELECT
                accounts.id AS accountID,
                COALESCE(accounts.opening_balance, 0) + COALESCE(SUM(entries.amount), 0) AS balance
            FROM accounts
            LEFT JOIN entries ON entries.account_id = accounts.id
            LEFT JOIN transactions
                ON transactions.id = entries.transaction_id
               AND transactions.state = 'cleared'
            WHERE accounts.is_group = 0
              AND (entries.id IS NULL OR transactions.id IS NOT NULL)
            GROUP BY accounts.id, accounts.opening_balance
            """

        return try databaseManager.dbQueue.read { db in
            let rows = try AccountBalanceRow.fetchAll(db, sql: sql)
            return Dictionary(uniqueKeysWithValues: rows.map { ($0.accountID, $0.balance) })
        }
    }

    func getAccount(id: Int64, db: Database) throws -> Account? {
        try Account.fetchOne(db, key: id)
    }

    func getAllAccounts(db: Database) throws -> [Account] {
        try Account
            .order(Account.Columns.sortOrder, Account.Columns.name)
            .fetchAll(db)
    }

    func getLeafAccounts(db: Database) throws -> [Account] {
        let childParentIDs = try Int64.fetchSet(
            db,
            sql: "SELECT DISTINCT parent_id FROM accounts WHERE parent_id IS NOT NULL"
        )

        return try Account
            .filter(Account.Columns.isGroup == false)
            .order(Account.Columns.sortOrder, Account.Columns.name)
            .fetchAll(db)
            .filter { account in
                guard let accountID = account.id else {
                    return false
                }
                return !childParentIDs.contains(accountID)
            }
    }

    func hasChildren(accountID: Int64, db: Database) throws -> Bool {
        try Account
            .filter(Account.Columns.parentID == accountID)
            .fetchCount(db) > 0
    }
}
