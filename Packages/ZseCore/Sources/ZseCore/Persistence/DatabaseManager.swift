import Foundation
import GRDB

final class DatabaseManager: @unchecked Sendable {
    static let shared: DatabaseManager = {
        do {
            return try DatabaseManager()
        } catch {
            fatalError("Failed to initialize database: \(error)")
        }
    }()

    private let configuration: Configuration
    private(set) var dbQueue: DatabaseQueue
    let databasePath: String
    let databaseFolderPath: String
    private(set) var migrationStatus: String

    convenience init() throws {
        try self.init(databasePath: Self.makeDatabasePath())
    }

    init(databasePath: String) throws {
        self.databasePath = databasePath
        self.databaseFolderPath = (databasePath as NSString).deletingLastPathComponent

        var configuration = Configuration()
        configuration.prepareDatabase { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }
        self.configuration = configuration

        self.dbQueue = try Self.openDatabaseQueue(path: databasePath, configuration: configuration)
        try Migrations.migrator.migrate(self.dbQueue)
        self.migrationStatus = "Applied"
    }

    func countRows(in tableName: String) throws -> Int {
        try dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(tableName)") ?? 0
        }
    }

    func writeInTransaction<T>(_ updates: (Database) throws -> T) throws -> T {
        try dbQueue.writeWithoutTransaction { db in
            var result: T?
            try db.inTransaction {
                result = try updates(db)
                return .commit
            }

            guard let result else {
                fatalError("Transaction completed without returning a result.")
            }

            return result
        }
    }

    func close() throws {
        try dbQueue.close()
    }

    func reopen() throws {
        self.dbQueue = try Self.openDatabaseQueue(path: databasePath, configuration: configuration)
        try Migrations.migrator.migrate(self.dbQueue)
        self.migrationStatus = "Applied"
    }

    private static func openDatabaseQueue(path: String, configuration: Configuration) throws -> DatabaseQueue {
        try DatabaseQueue(path: path, configuration: configuration)
    }

    private static func makeDatabasePath() throws -> String {
        let fileManager = FileManager.default
        let baseDirectory = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let appDirectory = baseDirectory
            .appendingPathComponent("net.bajancsalad.zse", isDirectory: true)
        try fileManager.createDirectory(
            at: appDirectory,
            withIntermediateDirectories: true,
            attributes: nil
        )
        return appDirectory.appendingPathComponent("zse.sqlite").path
    }
}
