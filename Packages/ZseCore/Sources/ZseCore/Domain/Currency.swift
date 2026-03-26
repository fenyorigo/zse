import Foundation
import GRDB

struct Currency: Codable, FetchableRecord, PersistableRecord, Identifiable {
    static let databaseTableName = "currencies"

    var id: String { code }
    var code: String
    var name: String
    var symbol: String?
    var decimals: Int

    enum Columns {
        static let code = Column("code")
        static let name = Column("name")
        static let symbol = Column("symbol")
        static let decimals = Column("decimals")
    }
}
