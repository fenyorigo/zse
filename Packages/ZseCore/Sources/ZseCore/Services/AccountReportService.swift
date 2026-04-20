import Foundation

struct AccountReportExportSummary {
    let exportedRowCount: Int
    let destinationURL: URL
}

private struct AccountReportRow {
    let date: String
    let status: String
    let accountPath: String
    let counterpartPath: String
    let categoryPath: String
    let description: String
    let memo: String
    let out: Double?
    let `in`: Double?
    let currency: String
    let runningBalance: Double
}

struct AccountReportService {
    private let accountRepository: AccountRepository
    private let transactionRepository: TransactionRepository

    init(
        accountRepository: AccountRepository,
        transactionRepository: TransactionRepository
    ) {
        self.accountRepository = accountRepository
        self.transactionRepository = transactionRepository
    }

    func defaultEndDateString() throws -> String {
        try transactionRepository.latestTransactionDateString() ?? "2100-12-31"
    }

    func makeDefaultExportURL(in directoryURL: URL) -> URL {
        directoryURL.appendingPathComponent("zse-report-\(Self.timestampFormatter.string(from: Date())).csv")
    }

    func exportAccountReport(
        selectedLeafAccountIDs: Set<Int64>,
        afterDate: String,
        beforeDate: String,
        destinationDirectoryURL: URL
    ) throws -> AccountReportExportSummary {
        let accounts = try accountRepository.getAllAccounts()
        let accountsByID = Dictionary(
            uniqueKeysWithValues: accounts.compactMap { account -> (Int64, Account)? in
                guard let accountID = account.id else { return nil }
                return (accountID, account)
            }
        )

        let leafAccounts = selectedLeafAccountIDs.compactMap { accountsByID[$0] }
            .sorted { lhs, rhs in
                buildAccountPath(for: lhs, accountsByID: accountsByID)
                    .localizedCaseInsensitiveCompare(buildAccountPath(for: rhs, accountsByID: accountsByID)) == .orderedAscending
            }

        var detailCache: [Int64: TransactionDetail] = [:]
        var rows: [AccountReportRow] = []

        for account in leafAccounts {
            guard let accountID = account.id else {
                continue
            }

            let transactions = try transactionRepository.fetchTransactions(forAccountID: accountID)
            let filteredTransactions = transactions.filter { item in
                item.txnDate >= afterDate && item.txnDate <= beforeDate
            }

            for item in filteredTransactions {
                let detail: TransactionDetail
                if let cached = detailCache[item.id] {
                    detail = cached
                } else {
                    guard let fetchedDetail = try transactionRepository.fetchTransactionDetail(transactionID: item.id) else {
                        continue
                    }
                    detailCache[item.id] = fetchedDetail
                    detail = fetchedDetail
                }

                rows.append(
                    makeRow(
                        item: item,
                        detail: detail,
                        currentAccount: account,
                        accountsByID: accountsByID
                    )
                )
            }
        }

        let destinationURL = makeDefaultExportURL(in: destinationDirectoryURL)
        let contents = makeFileContents(rows: rows)
        try contents.write(to: destinationURL, atomically: true, encoding: .utf8)

        return AccountReportExportSummary(
            exportedRowCount: rows.count,
            destinationURL: destinationURL
        )
    }

    private func makeRow(
        item: TransactionListItem,
        detail: TransactionDetail,
        currentAccount: Account,
        accountsByID: [Int64: Account]
    ) -> AccountReportRow {
        let currentAccountPath = buildAccountPath(for: currentAccount, accountsByID: accountsByID)
        let currentAccountID = currentAccount.id ?? 0
        let currentEntry = detail.entries.first { $0.accountID == currentAccountID }
        let otherEntries = detail.entries.filter { $0.accountID != currentAccountID }

        let counterpartPaths = otherEntries.compactMap { entry -> String? in
            guard let account = accountsByID[entry.accountID],
                  account.class == "asset" || account.class == "liability" else {
                return nil
            }
            return buildAccountPath(for: account, accountsByID: accountsByID)
        }

        let categoryPaths = otherEntries.compactMap { entry -> String? in
            guard let account = accountsByID[entry.accountID],
                  account.class == "income" || account.class == "expense" else {
                return nil
            }
            return buildAccountPath(for: account, accountsByID: accountsByID)
        }

        let memo = currentEntry?.memo
            ?? detail.memoSummary
            ?? ""

        return AccountReportRow(
            date: item.txnDate,
            status: displayTitle(for: item.state),
            accountPath: currentAccountPath,
            counterpartPath: counterpartPaths.sorted().joined(separator: ", "),
            categoryPath: categoryPaths.sorted().joined(separator: ", "),
            description: detail.description ?? "",
            memo: memo,
            out: item.outAmount,
            in: item.inAmount,
            currency: currentAccount.currency,
            runningBalance: displayRunningBalance(item.runningBalance, accountClass: currentAccount.class),
        )
    }

    private func makeFileContents(rows: [AccountReportRow]) -> String {
        let header = [
            "Date",
            "Status",
            "AccountPath",
            "CounterpartPath",
            "CategoryPath",
            "Description",
            "Memo",
            "Out",
            "In",
            "Currency",
            "RunningBalance"
        ].joined(separator: "\t")

        let body = rows.map { row in
            [
                row.date,
                row.status,
                row.accountPath,
                row.counterpartPath,
                row.categoryPath,
                row.description,
                row.memo,
                formatNumber(row.out),
                formatNumber(row.in),
                row.currency,
                formatNumber(row.runningBalance)
            ]
            .map(escapeTabDelimitedField)
            .joined(separator: "\t")
        }

        return ([header] + body).joined(separator: "\n") + "\n"
    }

    private func buildAccountPath(for account: Account, accountsByID: [Int64: Account]) -> String {
        var components = [account.name]
        var currentParentID = account.parentID

        while let parentID = currentParentID,
              let parent = accountsByID[parentID] {
            components.append(parent.name)
            currentParentID = parent.parentID
        }

        return components.reversed().joined(separator: ":")
    }

    private func displayRunningBalance(_ runningBalance: Double, accountClass: String) -> Double {
        switch accountClass {
        case "income", "liability":
            return -runningBalance
        default:
            return runningBalance
        }
    }

    private func displayTitle(for state: String) -> String {
        switch state {
        case "cleared":
            return "cleared"
        case "reconciling":
            return "pending"
        default:
            return "uncleared"
        }
    }

    private func formatNumber(_ value: Double?) -> String {
        guard let value else {
            return ""
        }
        return Self.numberFormatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
    }

    private func escapeTabDelimitedField(_ value: String) -> String {
        if value.contains("\t") || value.contains("\n") || value.contains("\"") {
            let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return value
    }

    private static let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.groupingSeparator = ""
        formatter.decimalSeparator = "."
        return formatter
    }()

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd-HH-mm"
        return formatter
    }()
}
