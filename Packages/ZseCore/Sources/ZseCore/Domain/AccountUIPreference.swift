import Foundation
import GRDB

struct AccountUIPreference: Codable, FetchableRecord, MutablePersistableRecord, Identifiable {
    static let databaseTableName = "account_ui_preferences"

    var accountID: Int64
    var transactionStatusFilter: String?
    var afterDateFilter: String?
    var beforeDateFilter: String?
    var createdAt: String
    var updatedAt: String

    var id: Int64 { accountID }

    init(
        accountID: Int64,
        transactionStatusFilter: String? = nil,
        afterDateFilter: String? = nil,
        beforeDateFilter: String? = nil,
        createdAt: String? = nil,
        updatedAt: String? = nil
    ) {
        let timestamp = Account.makeTimestamp()
        self.accountID = accountID
        self.transactionStatusFilter = transactionStatusFilter
        self.afterDateFilter = afterDateFilter
        self.beforeDateFilter = beforeDateFilter
        self.createdAt = createdAt ?? timestamp
        self.updatedAt = updatedAt ?? timestamp
    }

    enum Columns {
        static let accountID = Column("account_id")
        static let transactionStatusFilter = Column("transaction_status_filter")
        static let afterDateFilter = Column("after_date_filter")
        static let beforeDateFilter = Column("before_date_filter")
        static let createdAt = Column("created_at")
        static let updatedAt = Column("updated_at")
    }

    enum CodingKeys: String, CodingKey {
        case accountID = "account_id"
        case transactionStatusFilter = "transaction_status_filter"
        case afterDateFilter = "after_date_filter"
        case beforeDateFilter = "before_date_filter"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
