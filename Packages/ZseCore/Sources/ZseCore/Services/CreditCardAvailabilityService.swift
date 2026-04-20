import Foundation

struct CreditCardAvailabilitySnapshot {
    let effectiveUsedCredit: Double?
    let availableBeforeNextReimbursement: Double?
    let nextReimbursementDate: String?
}

struct CreditCardAvailabilityService {
    private static let creditCardSubtypes: Set<String> = [
        "credit",
        "credit_card"
    ]

    func snapshot(for account: Account, transactions: [TransactionListItem]) -> CreditCardAvailabilitySnapshot? {
        guard account.class == "liability",
              Self.creditCardSubtypes.contains(account.subtype) else {
            return nil
        }

        let orderedTransactions = sortTransactions(transactions)
        let nextReimbursementIndex = orderedTransactions.firstIndex { item in
            item.txnDate >= Self.todayDateString &&
            item.memoSummary == "Hitelkártya visszafizetés" &&
            (item.inAmount ?? 0) > 0
        }

        let effectiveUsedCredit = forecastMaximumUsedCredit(
            for: account,
            transactions: orderedTransactions,
            nextReimbursementIndex: nextReimbursementIndex
        )
        let availableBeforeNextReimbursement = account.creditLimit.flatMap { creditLimit in
            effectiveUsedCredit.map { max(0, creditLimit - $0) }
        }

        return CreditCardAvailabilitySnapshot(
            effectiveUsedCredit: effectiveUsedCredit,
            availableBeforeNextReimbursement: availableBeforeNextReimbursement,
            nextReimbursementDate: nextReimbursementIndex.map { orderedTransactions[$0].txnDate }
        )
    }

    private func forecastMaximumUsedCredit(
        for account: Account,
        transactions: [TransactionListItem],
        nextReimbursementIndex: Int?
    ) -> Double? {
        let currentIndex = transactions.lastIndex { $0.txnDate <= Self.todayDateString }
        let startIndex = currentIndex ?? 0
        let upperBound = nextReimbursementIndex ?? transactions.count

        guard startIndex < upperBound else {
            if let currentIndex {
                return max(0, displayRunningBalance(for: transactions[currentIndex], accountClass: account.class))
            }
            return max(0, account.openingBalance ?? 0)
        }

        var maximumUsedCredit = currentIndex.map {
            max(0, displayRunningBalance(for: transactions[$0], accountClass: account.class))
        } ?? max(0, account.openingBalance ?? 0)

        for index in startIndex..<upperBound {
            maximumUsedCredit = max(
                maximumUsedCredit,
                max(0, displayRunningBalance(for: transactions[index], accountClass: account.class))
            )
        }

        return maximumUsedCredit
    }

    private func displayRunningBalance(for item: TransactionListItem, accountClass: String) -> Double {
        displayRunningBalance(for: item.runningBalance, accountClass: accountClass)
    }

    private func displayRunningBalance(for runningBalance: Double, accountClass: String) -> Double {
        switch accountClass {
        case "income", "liability":
            return -runningBalance
        default:
            return runningBalance
        }
    }

    private func sortTransactions(_ transactions: [TransactionListItem]) -> [TransactionListItem] {
        transactions.sorted { lhs, rhs in
            if lhs.txnDate != rhs.txnDate {
                return lhs.txnDate < rhs.txnDate
            }
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt < rhs.createdAt
            }
            if lhs.transactionID != rhs.transactionID {
                return lhs.transactionID < rhs.transactionID
            }
            return lhs.firstEntryID < rhs.firstEntryID
        }
    }

    private static let todayDateString: String = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }()
}
