import Foundation
import GRDB

enum DatabaseWipeScope: String, CaseIterable, Identifiable {
    case transactionsOnly
    case operationalData
    case fullReset

    var id: String { rawValue }

    var title: String {
        switch self {
        case .transactionsOnly:
            return "Wipe Transactions Only"
        case .operationalData:
            return "Wipe Operational Data"
        case .fullReset:
            return "Full Reset"
        }
    }

    var explanation: String {
        switch self {
        case .transactionsOnly:
            return "Deletes transactions and entries. Accounts, currencies, partners, and recurring rules remain."
        case .operationalData:
            return "Deletes transactions, entries, recurring rules, and partners. Accounts and currencies remain."
        case .fullReset:
            return "Resets the database to a fresh initial state. Accounts, transactions, partners, recurring rules, and FX rates are removed. Seeded currencies remain."
        }
    }
}

struct DatabaseMaintenanceService {
    private let databaseManager: DatabaseManager
    private let appPreferencesRepository: AppPreferencesRepository
    private let fileManager = FileManager.default

    init(databaseManager: DatabaseManager, appPreferencesRepository: AppPreferencesRepository) {
        self.databaseManager = databaseManager
        self.appPreferencesRepository = appPreferencesRepository
    }

    func backupFolderURL() throws -> URL {
        let backupsURL: URL
        if let preferredPath = try appPreferencesRepository.backupDirectoryPath(),
           !preferredPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            backupsURL = URL(fileURLWithPath: preferredPath, isDirectory: true)
        } else {
            backupsURL = URL(fileURLWithPath: databaseManager.databaseFolderPath, isDirectory: true)
                .appendingPathComponent("Backups", isDirectory: true)
        }
        try fileManager.createDirectory(at: backupsURL, withIntermediateDirectories: true)
        return backupsURL
    }

    func makeTimestampedBackupURL(prefix: String) throws -> URL {
        try backupFolderURL().appendingPathComponent("\(prefix)_\(Self.timestampFileComponent()).sqlite")
    }

    func backupDatabase(to destinationURL: URL) throws {
        try prepareDestinationParentDirectory(for: destinationURL)
        try withClosedDatabase {
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.copyItem(at: activeDatabaseURL, to: destinationURL)
            try copySidecarFiles(from: activeDatabaseURL, to: destinationURL)
        }
    }

    func restoreDatabase(from backupURL: URL) throws -> URL {
        guard fileManager.fileExists(atPath: backupURL.path) else {
            throw DatabaseMaintenanceError.backupFileNotFound
        }

        try validateSQLiteFile(at: backupURL)
        let safetyBackupURL = try makeTimestampedBackupURL(prefix: "zse_pre_restore_backup")
        try backupDatabase(to: safetyBackupURL)

        let tempRestoreURL = URL(fileURLWithPath: databaseManager.databaseFolderPath, isDirectory: true)
            .appendingPathComponent("restore_\(Self.timestampFileComponent()).sqlite")

        if fileManager.fileExists(atPath: tempRestoreURL.path) {
            try fileManager.removeItem(at: tempRestoreURL)
        }

        try fileManager.copyItem(at: backupURL, to: tempRestoreURL)
        try copySidecarFiles(from: backupURL, to: tempRestoreURL)
        try validateSQLiteFile(at: tempRestoreURL)

        do {
            try withClosedDatabase {
                try removeSidecarFiles(at: activeDatabaseURL)
                if fileManager.fileExists(atPath: activeDatabaseURL.path) {
                    _ = try fileManager.replaceItemAt(activeDatabaseURL, withItemAt: tempRestoreURL)
                } else {
                    try fileManager.moveItem(at: tempRestoreURL, to: activeDatabaseURL)
                }
                try moveSidecarFiles(from: tempRestoreURL, to: activeDatabaseURL)
            }
        } catch {
            try? removeSQLiteFiles(at: tempRestoreURL)
            throw error
        }

        return safetyBackupURL
    }

    func wipeDatabase(scope: DatabaseWipeScope) throws {
        try databaseManager.writeInTransaction { db in
            switch scope {
            case .transactionsOnly:
                try wipeTransactionsOnly(db: db)
            case .operationalData:
                try wipeOperationalData(db: db)
            case .fullReset:
                try wipeFullReset(db: db)
            }
        }
    }

    private var activeDatabaseURL: URL {
        URL(fileURLWithPath: databaseManager.databasePath)
    }

    private func withClosedDatabase(_ operation: () throws -> Void) throws {
        try databaseManager.close()
        do {
            try operation()
            try databaseManager.reopen()
        } catch {
            try? databaseManager.reopen()
            throw error
        }
    }

    private func prepareDestinationParentDirectory(for url: URL) throws {
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }

    private func validateSQLiteFile(at url: URL) throws {
        let queue = try DatabaseQueue(path: url.path)
        defer { try? queue.close() }

        let requiredTables = Set(["currencies", "accounts", "transactions", "entries"])
        let existingTables = try queue.read { db in
            try Set(String.fetchAll(
                db,
                sql: "SELECT name FROM sqlite_master WHERE type = 'table'"
            ))
        }

        guard requiredTables.isSubset(of: existingTables) else {
            throw DatabaseMaintenanceError.invalidBackupFile
        }
    }

    private func wipeTransactionsOnly(db: Database) throws {
        try db.execute(sql: "DELETE FROM transactions")
    }

    private func wipeOperationalData(db: Database) throws {
        try db.execute(sql: "DELETE FROM transactions")
        try db.execute(sql: "DELETE FROM recurring_rules")
        try db.execute(sql: "DELETE FROM partners")
    }

    private func wipeFullReset(db: Database) throws {
        try db.execute(sql: "DELETE FROM transactions")
        try db.execute(sql: "DELETE FROM recurring_rules")
        try db.execute(sql: "DELETE FROM partners")
        try db.execute(sql: "DELETE FROM fx_rates")
        try db.execute(sql: "DELETE FROM accounts")
        try db.execute(sql: "DELETE FROM currencies")

        for currency in Migrations.defaultCurrencies {
            try currency.insert(db)
        }
    }

    private func removeSQLiteFiles(at baseURL: URL) throws {
        let candidates = [baseURL, sidecarURL(for: baseURL, suffix: "-wal"), sidecarURL(for: baseURL, suffix: "-shm")]
        for candidate in candidates where fileManager.fileExists(atPath: candidate.path) {
            try fileManager.removeItem(at: candidate)
        }
    }

    private func removeSidecarFiles(at baseURL: URL) throws {
        let candidates = [sidecarURL(for: baseURL, suffix: "-wal"), sidecarURL(for: baseURL, suffix: "-shm")]
        for candidate in candidates where fileManager.fileExists(atPath: candidate.path) {
            try fileManager.removeItem(at: candidate)
        }
    }

    private func copySidecarFiles(from sourceURL: URL, to destinationURL: URL) throws {
        for suffix in ["-wal", "-shm"] {
            let sourceSidecar = sidecarURL(for: sourceURL, suffix: suffix)
            let destinationSidecar = sidecarURL(for: destinationURL, suffix: suffix)
            guard fileManager.fileExists(atPath: sourceSidecar.path) else {
                continue
            }
            if fileManager.fileExists(atPath: destinationSidecar.path) {
                try fileManager.removeItem(at: destinationSidecar)
            }
            try fileManager.copyItem(at: sourceSidecar, to: destinationSidecar)
        }
    }

    private func moveSidecarFiles(from sourceURL: URL, to destinationURL: URL) throws {
        for suffix in ["-wal", "-shm"] {
            let sourceSidecar = sidecarURL(for: sourceURL, suffix: suffix)
            let destinationSidecar = sidecarURL(for: destinationURL, suffix: suffix)
            guard fileManager.fileExists(atPath: sourceSidecar.path) else {
                continue
            }
            if fileManager.fileExists(atPath: destinationSidecar.path) {
                try fileManager.removeItem(at: destinationSidecar)
            }
            try fileManager.moveItem(at: sourceSidecar, to: destinationSidecar)
        }
    }

    private func sidecarURL(for baseURL: URL, suffix: String) -> URL {
        URL(fileURLWithPath: baseURL.path + suffix)
    }

    private static func timestampFileComponent() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter.string(from: Date())
    }
}

enum DatabaseMaintenanceError: Error, LocalizedError {
    case backupFileNotFound
    case invalidBackupFile

    var errorDescription: String? {
        switch self {
        case .backupFileNotFound:
            return "The selected backup file could not be found."
        case .invalidBackupFile:
            return "The selected file is not a valid zsé database backup."
        }
    }
}
