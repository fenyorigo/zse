import Foundation
import GRDB

struct FxRate: Codable, FetchableRecord, MutablePersistableRecord, Identifiable {
    static let databaseTableName = "fx_rates"

    var id: Int64?
    var rateDate: String
    var currencyCode: String
    var hufRate: Double
    var source: String
    var downloadedAt: String

    init(
        id: Int64? = nil,
        rateDate: String,
        currencyCode: String,
        hufRate: Double,
        source: String = "MNB",
        downloadedAt: String? = nil
    ) {
        self.id = id
        self.rateDate = rateDate
        self.currencyCode = currencyCode
        self.hufRate = hufRate
        self.source = source
        self.downloadedAt = downloadedAt ?? FxRate.makeTimestamp()
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    enum Columns {
        static let id = Column("id")
        static let rateDate = Column("rate_date")
        static let currencyCode = Column("currency_code")
        static let hufRate = Column("huf_rate")
        static let source = Column("source")
        static let downloadedAt = Column("downloaded_at")
    }

    enum CodingKeys: String, CodingKey {
        case id
        case rateDate = "rate_date"
        case currencyCode = "currency_code"
        case hufRate = "huf_rate"
        case source
        case downloadedAt = "downloaded_at"
    }

    static func makeTimestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }
}
