import Foundation
import GRDB

struct AccountBalanceChartService {
    struct Presentation {
        let title: String
        let currency: String
        let startDate: Date
        let endDate: Date
        let seriesNames: [String]
        let points: [Point]
    }

    struct Point: Identifiable {
        let date: Date
        let seriesName: String
        let value: Double
        let lowerBound: Double
        let upperBound: Double

        var id: String {
            "\(seriesName)-\(Self.dateFormatter.string(from: date))"
        }

        private static let dateFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter
        }()
    }

    enum Result {
        case hidden
        case unavailable(String)
        case ready(Presentation)
    }

    private struct DailyChangeRow: Decodable, FetchableRecord {
        let accountID: Int64
        let txnDate: String
        let amount: Double
    }

    private let databaseManager: DatabaseManager
    private let accountRepository: AccountRepository

    init(databaseManager: DatabaseManager, accountRepository: AccountRepository) {
        self.databaseManager = databaseManager
        self.accountRepository = accountRepository
    }

    func buildChart(
        rootAccount: Account,
        afterDate: String,
        beforeDate: String,
        statusFilter: String
    ) throws -> Result {
        guard let rootAccountID = rootAccount.id else {
            return .hidden
        }

        let allAccounts = try accountRepository.getAllAccounts()
        let childMap = Dictionary(grouping: allAccounts, by: \.parentID)
        let descendantLeaves = relevantLeafAccounts(
            for: rootAccount,
            childMap: childMap
        )

        guard !descendantLeaves.isEmpty else {
            return .hidden
        }

        let currencies = Set(descendantLeaves.map(\.currency))
        guard currencies.count == 1, let currency = currencies.first else {
            return .unavailable("Chart is available for homogeneous-currency subtrees only.")
        }

        let leafAccountIDs = descendantLeaves.compactMap(\.id)
        guard !leafAccountIDs.isEmpty else {
            return .hidden
        }

        let afterDateValue = Self.dateFormatter.date(from: afterDate) ?? Self.defaultAfterDate
        let beforeDateValue = Self.dateFormatter.date(from: beforeDate) ?? Self.defaultBeforeDate
        guard afterDateValue <= beforeDateValue else {
            return .ready(
                Presentation(
                    title: rootAccount.name,
                    currency: currency,
                    startDate: afterDateValue,
                    endDate: beforeDateValue,
                    seriesNames: descendantLeaves.map(\.name),
                    points: []
                )
            )
        }

        let dailyChanges = try fetchDailyChanges(
            accountIDs: leafAccountIDs,
            beforeDate: beforeDate,
            statusFilter: statusFilter
        )

        var openingBalancesByAccountID = Dictionary(
            uniqueKeysWithValues: descendantLeaves.map { account in
                (account.id ?? 0, account.openingBalance ?? 0)
            }
        )
        var inRangeChanges: [String: [Int64: Double]] = [:]
        var dateStrings = Set<String>()

        for row in dailyChanges {
            if row.txnDate < afterDate {
                openingBalancesByAccountID[row.accountID, default: 0] += row.amount
            } else {
                inRangeChanges[row.txnDate, default: [:]][row.accountID, default: 0] += row.amount
                dateStrings.insert(row.txnDate)
            }
        }

        let orderedDateStrings = dateStrings.sorted()
        guard !orderedDateStrings.isEmpty else {
            return .ready(
                Presentation(
                    title: rootAccount.name,
                    currency: currency,
                    startDate: afterDateValue,
                    endDate: beforeDateValue,
                    seriesNames: descendantLeaves.map {
                        relativeAccountName(for: $0, rootAccountID: rootAccountID, allAccounts: allAccounts)
                    },
                    points: []
                )
            )
        }

        var runningBalances = openingBalancesByAccountID
        var points: [Point] = []

        for dateString in orderedDateStrings {
            guard let date = Self.dateFormatter.date(from: dateString) else {
                continue
            }

            let dailyDelta = inRangeChanges[dateString] ?? [:]
            for accountID in leafAccountIDs {
                runningBalances[accountID, default: 0] += dailyDelta[accountID, default: 0]
            }

            var lowerBound = 0.0
            for account in descendantLeaves {
                guard let accountID = account.id else {
                    continue
                }

                let value = normalizedBalance(
                    runningBalances[accountID, default: 0],
                    accountClass: account.class
                )
                let upperBound = lowerBound + value
                points.append(
                    Point(
                        date: date,
                        seriesName: relativeAccountName(for: account, rootAccountID: rootAccountID, allAccounts: allAccounts),
                        value: value,
                        lowerBound: lowerBound,
                        upperBound: upperBound
                    )
                )
                lowerBound = upperBound
            }
        }

        return .ready(
            Presentation(
                title: rootAccount.name,
                currency: currency,
                startDate: orderedDateStrings.first.flatMap(Self.dateFormatter.date(from:)) ?? afterDateValue,
                endDate: orderedDateStrings.last.flatMap(Self.dateFormatter.date(from:)) ?? beforeDateValue,
                seriesNames: descendantLeaves.map {
                    relativeAccountName(for: $0, rootAccountID: rootAccountID, allAccounts: allAccounts)
                },
                points: points
            )
        )
    }

    private func relevantLeafAccounts(
        for rootAccount: Account,
        childMap: [Int64?: [Account]]
    ) -> [Account] {
        guard let rootAccountID = rootAccount.id else {
            return []
        }

        var result: [Account] = []

        func collectChildren(of parentID: Int64) {
            let children = childMap[parentID] ?? []
            for child in children {
                guard let childID = child.id else {
                    continue
                }

                let grandChildren = childMap[childID] ?? []
                if grandChildren.isEmpty {
                    result.append(child)
                } else {
                    collectChildren(of: childID)
                }
            }
        }

        collectChildren(of: rootAccountID)

        if result.isEmpty {
            let rootChildren = childMap[rootAccountID] ?? []
            if rootChildren.isEmpty, rootAccount.isGroup == false {
                result = [rootAccount]
            }
        }

        return result.sorted { lhs, rhs in
            if lhs.sortOrder != rhs.sortOrder {
                return lhs.sortOrder < rhs.sortOrder
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private func fetchDailyChanges(
        accountIDs: [Int64],
        beforeDate: String,
        statusFilter: String
    ) throws -> [DailyChangeRow] {
        let placeholders = Array(repeating: "?", count: accountIDs.count).joined(separator: ", ")
        var arguments = StatementArguments(accountIDs)
        arguments += [beforeDate]

        let statusCondition: String
        switch statusFilter {
        case "clearedOnly":
            statusCondition = "AND transactions.state = 'cleared'"
        case "pendingOnly":
            statusCondition = "AND transactions.state = 'reconciling'"
        case "hideCleared":
            statusCondition = "AND transactions.state IN ('uncleared', 'reconciling')"
        default:
            statusCondition = ""
        }

        let sql = """
            SELECT
                entries.account_id AS accountID,
                transactions.txn_date AS txnDate,
                SUM(entries.amount) AS amount
            FROM entries
            INNER JOIN transactions ON transactions.id = entries.transaction_id
            WHERE entries.account_id IN (\(placeholders))
              AND transactions.txn_date <= ?
              \(statusCondition)
            GROUP BY entries.account_id, transactions.txn_date
            ORDER BY transactions.txn_date ASC, entries.account_id ASC
            """

        return try databaseManager.dbQueue.read { db in
            try DailyChangeRow.fetchAll(db, sql: sql, arguments: arguments)
        }
    }

    private func relativeAccountName(
        for account: Account,
        rootAccountID: Int64,
        allAccounts: [Account]
    ) -> String {
        let accountPairs: [(Int64, Account)] = allAccounts.compactMap { account in
            guard let accountID = account.id else {
                return nil
            }
            return (accountID, account)
        }
        let accountsByID = Dictionary(uniqueKeysWithValues: accountPairs)

        var components = [account.name]
        var currentParentID = account.parentID

        while let parentID = currentParentID,
              parentID != rootAccountID,
              let parentAccount = accountsByID[parentID] {
            components.append(parentAccount.name)
            currentParentID = parentAccount.parentID
        }

        return components.reversed().joined(separator: " > ")
    }

    private func normalizedBalance(_ balance: Double, accountClass: String) -> Double {
        shouldInvertBalanceDisplaySign(for: accountClass) ? -balance : balance
    }

    private func shouldInvertBalanceDisplaySign(for accountClass: String) -> Bool {
        accountClass == "income" || accountClass == "liability"
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let defaultAfterDate: Date = {
        dateFormatter.date(from: "1960-01-01") ?? Date.distantPast
    }()

    private static let defaultBeforeDate: Date = {
        dateFormatter.date(from: "2100-12-31") ?? Date.distantFuture
    }()
}
