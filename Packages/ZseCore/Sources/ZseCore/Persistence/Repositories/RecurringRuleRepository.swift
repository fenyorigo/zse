import GRDB

struct RecurringRuleRepository {
    private let databaseManager: DatabaseManager

    init(databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager
    }

    func writeInTransaction<T>(_ updates: (Database) throws -> T) throws -> T {
        try databaseManager.writeInTransaction(updates)
    }

    func createRule(_ rule: inout RecurringRule) throws {
        try databaseManager.dbQueue.write { db in
            try rule.insert(db)
        }
    }

    func createRule(_ rule: inout RecurringRule, db: Database) throws {
        try rule.insert(db)
    }

    func updateRule(_ rule: RecurringRule) throws {
        try databaseManager.dbQueue.write { db in
            try rule.update(db)
        }
    }

    func updateRule(_ rule: RecurringRule, db: Database) throws {
        try rule.update(db)
    }

    func fetchAllRules() throws -> [RecurringRule] {
        try databaseManager.dbQueue.read { db in
            try RecurringRule
                .order(RecurringRule.Columns.name)
                .fetchAll(db)
        }
    }

    func fetchRules(nextDueOnOrBefore date: String, db: Database) throws -> [RecurringRule] {
        try RecurringRule
            .filter(RecurringRule.Columns.isActive == true)
            .filter(RecurringRule.Columns.nextDueDate != nil)
            .filter(RecurringRule.Columns.nextDueDate <= date)
            .order(RecurringRule.Columns.nextDueDate, RecurringRule.Columns.id)
            .fetchAll(db)
    }

    func hasGeneratedOccurrence(ruleID: Int64, occurrenceDate: String, db: Database) throws -> Bool {
        try Transaction
            .filter(Transaction.Columns.recurringRuleID == ruleID)
            .filter(Transaction.Columns.recurringOccurrenceDate == occurrenceDate)
            .fetchCount(db) > 0
    }

    func generatedOccurrenceCount(ruleID: Int64, db: Database) throws -> Int {
        try Transaction
            .filter(Transaction.Columns.recurringRuleID == ruleID)
            .fetchCount(db)
    }
}
