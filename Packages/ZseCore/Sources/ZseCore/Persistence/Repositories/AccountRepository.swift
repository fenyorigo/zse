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

    func setHidden(_ isHidden: Bool, forAccountID accountID: Int64) throws {
        try databaseManager.writeInTransaction { db in
            let accounts = try getAllAccounts(db: db)
            var accountsByID = Dictionary(
                uniqueKeysWithValues: accounts.compactMap { account -> (Int64, Account)? in
                    guard let accountID = account.id else {
                        return nil
                    }
                    return (accountID, account)
                }
            )
            let childIDsByParentID = Dictionary(grouping: accounts.compactMap { account -> (Int64, Int64)? in
                guard let accountID = account.id,
                      let parentID = account.parentID else {
                    return nil
                }
                return (parentID, accountID)
            }, by: \.0).mapValues { pairs in
                pairs.map(\.1)
            }

            guard let targetAccount = accountsByID[accountID] else {
                return
            }

            let updatedAt = Account.makeTimestamp()

            func descendantIDs(for rootAccountID: Int64) -> [Int64] {
                var orderedIDs: [Int64] = []
                var stack = [rootAccountID]

                while let currentID = stack.popLast() {
                    orderedIDs.append(currentID)
                    let childIDs = childIDsByParentID[currentID] ?? []
                    stack.append(contentsOf: childIDs.reversed())
                }

                return orderedIDs
            }

            func updateHiddenState(accountID: Int64, isHidden: Bool) throws {
                guard var account = accountsByID[accountID] else {
                    return
                }

                guard account.isHidden != isHidden else {
                    return
                }

                account.isHidden = isHidden
                account.updatedAt = updatedAt
                try account.update(db)
                accountsByID[accountID] = account
            }

            if isHidden {
                for descendantAccountID in descendantIDs(for: accountID) {
                    try updateHiddenState(accountID: descendantAccountID, isHidden: true)
                }

                var currentParentID = targetAccount.parentID
                while let parentID = currentParentID {
                    guard let parentAccount = accountsByID[parentID] else {
                        break
                    }

                    let childIDs = childIDsByParentID[parentID] ?? []
                    let allChildrenHidden = !childIDs.isEmpty && childIDs.allSatisfy { childID in
                        accountsByID[childID]?.isHidden == true
                    }
                    try updateHiddenState(accountID: parentID, isHidden: allChildrenHidden)
                    currentParentID = parentAccount.parentID
                }
            } else {
                for descendantAccountID in descendantIDs(for: accountID) {
                    try updateHiddenState(accountID: descendantAccountID, isHidden: false)
                }

                var currentParentID = targetAccount.parentID
                while let parentID = currentParentID {
                    guard let parentAccount = accountsByID[parentID] else {
                        break
                    }

                    try updateHiddenState(accountID: parentID, isHidden: false)
                    currentParentID = parentAccount.parentID
                }
            }
        }
    }

    func applyVisibleLeafAccountIDs(_ visibleLeafAccountIDs: Set<Int64>) throws {
        try databaseManager.writeInTransaction { db in
            let accounts = try getAllAccounts(db: db)
            let managedAccounts = accounts.filter { account in
                account.class == "asset" || account.class == "liability"
            }
            var accountsByID = Dictionary(
                uniqueKeysWithValues: managedAccounts.compactMap { account -> (Int64, Account)? in
                    guard let accountID = account.id else {
                        return nil
                    }
                    return (accountID, account)
                }
            )
            let childIDsByParentID = Dictionary(grouping: managedAccounts.compactMap { account -> (Int64, Int64)? in
                guard let accountID = account.id,
                      let parentID = account.parentID,
                      accountsByID[parentID] != nil else {
                    return nil
                }
                return (parentID, accountID)
            }, by: \.0).mapValues { pairs in
                pairs.map(\.1)
            }
            let updatedAt = Account.makeTimestamp()

            func applyVisibility(accountID: Int64) throws -> Bool {
                guard var account = accountsByID[accountID] else {
                    return false
                }

                let childIDs = childIDsByParentID[accountID] ?? []
                let isVisible: Bool
                if childIDs.isEmpty {
                    isVisible = visibleLeafAccountIDs.contains(accountID)
                } else {
                    var hasVisibleChild = false
                    for childID in childIDs {
                        if try applyVisibility(accountID: childID) {
                            hasVisibleChild = true
                        }
                    }
                    isVisible = hasVisibleChild
                }

                let shouldBeHidden = !isVisible
                if account.isHidden != shouldBeHidden {
                    account.isHidden = shouldBeHidden
                    account.updatedAt = updatedAt
                    try account.update(db)
                    accountsByID[accountID] = account
                }

                return isVisible
            }

            let rootIDs = managedAccounts.compactMap { account -> Int64? in
                guard let accountID = account.id else {
                    return nil
                }
                guard let parentID = account.parentID else {
                    return accountID
                }
                return accountsByID[parentID] == nil ? accountID : nil
            }

            for rootID in rootIDs {
                _ = try applyVisibility(accountID: rootID)
            }
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
