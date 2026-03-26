import Foundation
import GRDB

struct Account: Codable, FetchableRecord, MutablePersistableRecord, Identifiable {
    static let databaseTableName = "accounts"

    var id: Int64?
    var parentID: Int64?
    var name: String
    var `class`: String
    var subtype: String
    var currency: String
    var isGroup: Bool
    var isHidden: Bool
    var includeInNetWorth: Bool
    var accumulationCurrency: String?
    var creditLimit: Double?
    var openingBalance: Double?
    var openingBalanceDate: String?
    var sortOrder: Int
    var createdAt: String
    var updatedAt: String

    init(
        id: Int64? = nil,
        parentID: Int64? = nil,
        name: String,
        class: String,
        subtype: String,
        currency: String,
        isGroup: Bool = false,
        isHidden: Bool = false,
        includeInNetWorth: Bool = true,
        accumulationCurrency: String? = nil,
        creditLimit: Double? = nil,
        openingBalance: Double? = nil,
        openingBalanceDate: String? = nil,
        sortOrder: Int = 0,
        createdAt: String? = nil,
        updatedAt: String? = nil
    ) {
        let timestamp = Account.makeTimestamp()
        self.id = id
        self.parentID = parentID
        self.name = name
        self.class = `class`
        self.subtype = subtype
        self.currency = currency
        self.isGroup = isGroup
        self.isHidden = isHidden
        self.includeInNetWorth = includeInNetWorth
        self.accumulationCurrency = accumulationCurrency
        self.creditLimit = creditLimit
        self.openingBalance = openingBalance
        self.openingBalanceDate = openingBalanceDate
        self.sortOrder = sortOrder
        self.createdAt = createdAt ?? timestamp
        self.updatedAt = updatedAt ?? timestamp
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    enum Columns {
        static let id = Column("id")
        static let parentID = Column("parent_id")
        static let name = Column("name")
        static let accountClass = Column("class")
        static let subtype = Column("subtype")
        static let currency = Column("currency")
        static let isGroup = Column("is_group")
        static let isHidden = Column("is_hidden")
        static let includeInNetWorth = Column("include_in_net_worth")
        static let accumulationCurrency = Column("accumulation_currency")
        static let creditLimit = Column("credit_limit")
        static let openingBalance = Column("opening_balance")
        static let openingBalanceDate = Column("opening_balance_date")
        static let sortOrder = Column("sort_order")
        static let createdAt = Column("created_at")
        static let updatedAt = Column("updated_at")
    }

    enum CodingKeys: String, CodingKey {
        case id
        case parentID = "parent_id"
        case name
        case `class` = "class"
        case subtype
        case currency
        case isGroup = "is_group"
        case isHidden = "is_hidden"
        case includeInNetWorth = "include_in_net_worth"
        case accumulationCurrency = "accumulation_currency"
        case creditLimit = "credit_limit"
        case openingBalance = "opening_balance"
        case openingBalanceDate = "opening_balance_date"
        case sortOrder = "sort_order"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    static func makeTimestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }
}
