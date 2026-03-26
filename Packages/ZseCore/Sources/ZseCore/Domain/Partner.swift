import Foundation
import GRDB

struct Partner: Codable, FetchableRecord, MutablePersistableRecord, Identifiable {
    static let databaseTableName = "partners"

    var id: Int64?
    var name: String
    var notes: String?
    var isActive: Bool

    init(
        id: Int64? = nil,
        name: String,
        notes: String? = nil,
        isActive: Bool = true
    ) {
        self.id = id
        self.name = name
        self.notes = notes
        self.isActive = isActive
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    enum Columns {
        static let id = Column("id")
        static let name = Column("name")
        static let notes = Column("notes")
        static let isActive = Column("is_active")
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case notes
        case isActive = "is_active"
    }
}
