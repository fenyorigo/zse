import GRDB

struct FxRateRepository {
    private let databaseManager: DatabaseManager

    init(databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager
    }

    func upsertRates(_ rates: [FxRate]) throws {
        guard !rates.isEmpty else {
            return
        }

        try databaseManager.dbQueue.write { db in
            for rate in rates {
                try db.execute(
                    sql: """
                        INSERT INTO fx_rates (rate_date, currency_code, huf_rate, source, downloaded_at)
                        VALUES (?, ?, ?, ?, ?)
                        ON CONFLICT(rate_date, currency_code, source)
                        DO UPDATE SET
                            huf_rate = excluded.huf_rate,
                            downloaded_at = excluded.downloaded_at
                        """,
                    arguments: [
                        rate.rateDate,
                        rate.currencyCode,
                        rate.hufRate,
                        rate.source,
                        rate.downloadedAt
                    ]
                )
            }
        }
    }

    func latestStoredRateDate(source: String = "MNB") throws -> String? {
        try databaseManager.dbQueue.read { db in
            try String.fetchOne(
                db,
                sql: """
                    SELECT MAX(rate_date)
                    FROM fx_rates
                    WHERE source = ?
                    """,
                arguments: [source]
            )
        }
    }

    func hufRate(
        for currencyCode: String,
        onOrBefore rateDate: String,
        source: String = "MNB"
    ) throws -> Double? {
        if currencyCode == "HUF" {
            return 1.0
        }

        return try databaseManager.dbQueue.read { db in
            try Double.fetchOne(
                db,
                sql: """
                    SELECT huf_rate
                    FROM fx_rates
                    WHERE currency_code = ?
                      AND source = ?
                      AND rate_date <= ?
                    ORDER BY rate_date DESC
                    LIMIT 1
                    """,
                arguments: [currencyCode, source, rateDate]
            )
        }
    }

    func relevantCurrencyCodes() throws -> Set<String> {
        try databaseManager.dbQueue.read { db in
            let rows = try String.fetchAll(
                db,
                sql: """
                    SELECT DISTINCT currency
                    FROM accounts
                    WHERE currency IS NOT NULL
                    UNION
                    SELECT DISTINCT currency
                    FROM entries
                    WHERE currency IS NOT NULL
                    """
            )
            return Set(rows)
        }
    }
}
