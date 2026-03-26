import Foundation
import GRDB

enum RecurringTransactionType: String, CaseIterable, Codable, Identifiable {
    case income
    case expense
    case transfer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .income:
            return "Income"
        case .expense:
            return "Expense"
        case .transfer:
            return "Transfer"
        }
    }
}

enum RecurrenceType: String, CaseIterable, Codable, Identifiable {
    case daily
    case weekly
    case monthly
    case monthlyFixedDay = "monthly_fixed_day"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .daily:
            return "Daily"
        case .weekly:
            return "Weekly"
        case .monthly:
            return "Monthly"
        case .monthlyFixedDay:
            return "Monthly Fixed Day"
        }
    }
}

enum RecurringEndMode: String, CaseIterable, Codable, Identifiable {
    case none
    case count
    case date

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none:
            return "No End"
        case .count:
            return "End After N Transactions"
        case .date:
            return "End On Date"
        }
    }
}

struct RecurringRule: Codable, FetchableRecord, MutablePersistableRecord, Identifiable {
    static let databaseTableName = "recurring_rules"

    var id: Int64?
    var name: String
    var transactionType: RecurringTransactionType
    var sourceAccountID: Int64?
    var targetAccountID: Int64?
    var categoryAccountID: Int64?
    var amount: Double
    var currency: String
    var description: String?
    var memo: String?
    var defaultState: String
    var recurrenceType: RecurrenceType
    var intervalN: Int
    var dayOfMonth: Int?
    var startDate: String
    var endMode: RecurringEndMode
    var maxOccurrences: Int?
    var endDate: String?
    var nextDueDate: String?
    var isActive: Bool
    var createdAt: String
    var updatedAt: String

    init(
        id: Int64? = nil,
        name: String,
        transactionType: RecurringTransactionType,
        sourceAccountID: Int64? = nil,
        targetAccountID: Int64? = nil,
        categoryAccountID: Int64? = nil,
        amount: Double,
        currency: String,
        description: String? = nil,
        memo: String? = nil,
        defaultState: String = "uncleared",
        recurrenceType: RecurrenceType,
        intervalN: Int = 1,
        dayOfMonth: Int? = nil,
        startDate: String,
        endMode: RecurringEndMode = .none,
        maxOccurrences: Int? = nil,
        endDate: String? = nil,
        nextDueDate: String? = nil,
        isActive: Bool = true,
        createdAt: String? = nil,
        updatedAt: String? = nil
    ) {
        let timestamp = Account.makeTimestamp()
        self.id = id
        self.name = name
        self.transactionType = transactionType
        self.sourceAccountID = sourceAccountID
        self.targetAccountID = targetAccountID
        self.categoryAccountID = categoryAccountID
        self.amount = amount
        self.currency = currency
        self.description = description
        self.memo = memo
        self.defaultState = defaultState
        self.recurrenceType = recurrenceType
        self.intervalN = intervalN
        self.dayOfMonth = dayOfMonth
        self.startDate = startDate
        self.endMode = endMode
        self.maxOccurrences = maxOccurrences
        self.endDate = endDate
        self.nextDueDate = nextDueDate ?? startDate
        self.isActive = isActive
        self.createdAt = createdAt ?? timestamp
        self.updatedAt = updatedAt ?? timestamp
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    enum Columns {
        static let id = Column("id")
        static let name = Column("name")
        static let transactionType = Column("transaction_type")
        static let sourceAccountID = Column("source_account_id")
        static let targetAccountID = Column("target_account_id")
        static let categoryAccountID = Column("category_account_id")
        static let amount = Column("amount")
        static let currency = Column("currency")
        static let description = Column("description")
        static let memo = Column("memo")
        static let defaultState = Column("default_state")
        static let recurrenceType = Column("recurrence_type")
        static let intervalN = Column("interval_n")
        static let dayOfMonth = Column("day_of_month")
        static let startDate = Column("start_date")
        static let endMode = Column("end_mode")
        static let maxOccurrences = Column("max_occurrences")
        static let endDate = Column("end_date")
        static let nextDueDate = Column("next_due_date")
        static let isActive = Column("is_active")
        static let createdAt = Column("created_at")
        static let updatedAt = Column("updated_at")
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case transactionType = "transaction_type"
        case sourceAccountID = "source_account_id"
        case targetAccountID = "target_account_id"
        case categoryAccountID = "category_account_id"
        case amount
        case currency
        case description
        case memo
        case defaultState = "default_state"
        case recurrenceType = "recurrence_type"
        case intervalN = "interval_n"
        case dayOfMonth = "day_of_month"
        case startDate = "start_date"
        case endMode = "end_mode"
        case maxOccurrences = "max_occurrences"
        case endDate = "end_date"
        case nextDueDate = "next_due_date"
        case isActive = "is_active"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
