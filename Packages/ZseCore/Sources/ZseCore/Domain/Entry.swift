import Foundation
import GRDB

struct Entry: Codable, FetchableRecord, MutablePersistableRecord, Identifiable {
    static let databaseTableName = "entries"

    var id: Int64?
    var transactionID: Int64?
    var accountID: Int64
    var amount: Double
    var currency: String
    var partnerID: Int64?
    var memo: String?
    var createdAt: String

    init(
        id: Int64? = nil,
        transactionID: Int64? = nil,
        accountID: Int64,
        amount: Double,
        currency: String,
        partnerID: Int64? = nil,
        memo: String? = nil,
        createdAt: String? = nil
    ) {
        self.id = id
        self.transactionID = transactionID
        self.accountID = accountID
        self.amount = amount
        self.currency = currency
        self.partnerID = partnerID
        self.memo = memo
        self.createdAt = createdAt ?? Entry.makeTimestamp()
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    enum Columns {
        static let id = Column("id")
        static let transactionID = Column("transaction_id")
        static let accountID = Column("account_id")
        static let amount = Column("amount")
        static let currency = Column("currency")
        static let partnerID = Column("partner_id")
        static let memo = Column("memo")
        static let createdAt = Column("created_at")
    }

    enum CodingKeys: String, CodingKey {
        case id
        case transactionID = "transaction_id"
        case accountID = "account_id"
        case amount
        case currency
        case partnerID = "partner_id"
        case memo
        case createdAt = "created_at"
    }

    private static func makeTimestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }
}
