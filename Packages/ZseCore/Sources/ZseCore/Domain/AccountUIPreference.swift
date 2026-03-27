import Foundation
import GRDB

struct AccountUIPreference: Codable, FetchableRecord, MutablePersistableRecord, Identifiable {
    static let databaseTableName = "account_ui_preferences"

    var accountID: Int64
    var transactionStatusFilter: String?
    var createdAt: String
    var updatedAt: String

    var id: Int64 { accountID }

    init(
        accountID: Int64,
        transactionStatusFilter: String? = nil,
        createdAt: String? = nil,
        updatedAt: String? = nil
    ) {
        let timestamp = Account.makeTimestamp()
        self.accountID = accountID
        self.transactionStatusFilter = transactionStatusFilter
        self.createdAt = createdAt ?? timestamp
        self.updatedAt = updatedAt ?? timestamp
    }

    enum Columns {
        static let accountID = Column("account_id")
        static let transactionStatusFilter = Column("transaction_status_filter")
        static let createdAt = Column("created_at")
        static let updatedAt = Column("updated_at")
    }

    enum CodingKeys: String, CodingKey {
        case accountID = "account_id"
        case transactionStatusFilter = "transaction_status_filter"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
