import Foundation
import GRDB

struct AppPreferencesRepository {
    private let databaseManager: DatabaseManager

    init(databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager
    }

    func fetchPreferences() throws -> AppPreferences {
        try databaseManager.dbQueue.write { db in
            if let preferences = try AppPreferences.fetchOne(db, key: 1) {
                return preferences
            }

            var preferences = AppPreferences()
            try preferences.insert(db)
            return preferences
        }
    }

    func backupDirectoryPath() throws -> String? {
        try databaseManager.dbQueue.read { db in
            try AppPreferences.fetchOne(db, key: 1)?.backupDirectoryPath
        }
    }

    func backupDirectoryBookmarkData() throws -> Data? {
        try databaseManager.dbQueue.read { db in
            try AppPreferences.fetchOne(db, key: 1)?.backupDirectoryBookmarkData
        }
    }

    func setBackupDirectory(path: String?, bookmarkData: Data?) throws {
        try databaseManager.writeInTransaction { db in
            let existingPreferences = try AppPreferences.fetchOne(db, key: 1)
            var preferences = existingPreferences ?? AppPreferences()
            preferences.backupDirectoryPath = path
            preferences.backupDirectoryBookmarkData = bookmarkData
            preferences.updatedAt = Account.makeTimestamp()

            if existingPreferences == nil {
                try preferences.insert(db)
            } else {
                try preferences.update(db)
            }
        }
    }
}
