import Foundation
import GRDB

struct AccountUIPreferenceRepository {
    private let databaseManager: DatabaseManager

    init(databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager
    }

    func savedTransactionStatusFilter(accountID: Int64) throws -> String? {
        try databaseManager.dbQueue.read { db in
            try AccountUIPreference.fetchOne(db, key: accountID)?.transactionStatusFilter
        }
    }

    func saveTransactionStatusFilter(accountID: Int64, filter: String) throws {
        try databaseManager.writeInTransaction { db in
            let existingPreference = try AccountUIPreference.fetchOne(db, key: accountID)
            var preference = existingPreference ?? AccountUIPreference(accountID: accountID)
            preference.transactionStatusFilter = filter
            preference.updatedAt = Account.makeTimestamp()

            if existingPreference == nil {
                try preference.insert(db)
            } else {
                try preference.update(db)
            }
        }
    }
}
