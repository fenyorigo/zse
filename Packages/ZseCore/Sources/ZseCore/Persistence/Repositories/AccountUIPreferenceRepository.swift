import Foundation
import GRDB

struct AccountUIPreferenceRepository {
    private let databaseManager: DatabaseManager

    init(databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager
    }

    func savedPreference(accountID: Int64) throws -> AccountUIPreference? {
        try databaseManager.dbQueue.read { db in
            try AccountUIPreference.fetchOne(db, key: accountID)
        }
    }

    func savePreference(
        accountID: Int64,
        transactionStatusFilter: String,
        afterDateFilter: String?,
        beforeDateFilter: String?
    ) throws {
        try databaseManager.writeInTransaction { db in
            let existingPreference = try AccountUIPreference.fetchOne(db, key: accountID)
            var preference = existingPreference ?? AccountUIPreference(accountID: accountID)
            preference.transactionStatusFilter = transactionStatusFilter
            preference.afterDateFilter = afterDateFilter
            preference.beforeDateFilter = beforeDateFilter
            preference.updatedAt = Account.makeTimestamp()

            if existingPreference == nil {
                try preference.insert(db)
            } else {
                try preference.update(db)
            }
        }
    }
}
