import GRDB

struct CurrencyRepository {
    private let databaseManager: DatabaseManager

    init(databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager
    }

    func getAllCurrencies() throws -> [Currency] {
        try databaseManager.dbQueue.read { db in
            try Currency
                .order(Currency.Columns.code)
                .fetchAll(db)
        }
    }
}
