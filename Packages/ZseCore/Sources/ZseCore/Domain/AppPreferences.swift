import Foundation
import GRDB

struct AppPreferences: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "app_preferences"

    var id: Int64
    var backupDirectoryPath: String?
    var backupDirectoryBookmarkData: Data?
    var createdAt: String
    var updatedAt: String

    init(
        id: Int64 = 1,
        backupDirectoryPath: String? = nil,
        backupDirectoryBookmarkData: Data? = nil,
        createdAt: String? = nil,
        updatedAt: String? = nil
    ) {
        let timestamp = Account.makeTimestamp()
        self.id = id
        self.backupDirectoryPath = backupDirectoryPath
        self.backupDirectoryBookmarkData = backupDirectoryBookmarkData
        self.createdAt = createdAt ?? timestamp
        self.updatedAt = updatedAt ?? timestamp
    }

    enum Columns {
        static let id = Column("id")
        static let backupDirectoryPath = Column("backup_directory_path")
        static let backupDirectoryBookmarkData = Column("backup_directory_bookmark_data")
        static let createdAt = Column("created_at")
        static let updatedAt = Column("updated_at")
    }

    enum CodingKeys: String, CodingKey {
        case id
        case backupDirectoryPath = "backup_directory_path"
        case backupDirectoryBookmarkData = "backup_directory_bookmark_data"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
