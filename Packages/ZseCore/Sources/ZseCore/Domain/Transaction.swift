import Foundation
import GRDB

struct Transaction: Codable, FetchableRecord, MutablePersistableRecord, Identifiable {
    static let databaseTableName = "transactions"

    var id: Int64?
    var txnDate: String
    var description: String?
    var state: String
    var statusWarningFlag: Bool
    var statusWarningReason: String?
    var recurringRuleID: Int64?
    var recurringOccurrenceDate: String?
    var createdAt: String
    var updatedAt: String

    init(
        id: Int64? = nil,
        txnDate: String,
        description: String? = nil,
        state: String = "uncleared",
        statusWarningFlag: Bool = false,
        statusWarningReason: String? = nil,
        recurringRuleID: Int64? = nil,
        recurringOccurrenceDate: String? = nil,
        createdAt: String? = nil,
        updatedAt: String? = nil
    ) {
        let timestamp = Transaction.makeTimestamp()
        self.id = id
        self.txnDate = txnDate
        self.description = description
        self.state = state
        self.statusWarningFlag = statusWarningFlag
        self.statusWarningReason = statusWarningReason
        self.recurringRuleID = recurringRuleID
        self.recurringOccurrenceDate = recurringOccurrenceDate
        self.createdAt = createdAt ?? timestamp
        self.updatedAt = updatedAt ?? timestamp
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    enum Columns {
        static let id = Column("id")
        static let txnDate = Column("txn_date")
        static let description = Column("description")
        static let state = Column("state")
        static let statusWarningFlag = Column("status_warning_flag")
        static let statusWarningReason = Column("status_warning_reason")
        static let recurringRuleID = Column("recurring_rule_id")
        static let recurringOccurrenceDate = Column("recurring_occurrence_date")
        static let createdAt = Column("created_at")
        static let updatedAt = Column("updated_at")
    }

    enum CodingKeys: String, CodingKey {
        case id
        case txnDate = "txn_date"
        case description
        case state
        case statusWarningFlag = "status_warning_flag"
        case statusWarningReason = "status_warning_reason"
        case recurringRuleID = "recurring_rule_id"
        case recurringOccurrenceDate = "recurring_occurrence_date"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    private static func makeTimestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }
}
