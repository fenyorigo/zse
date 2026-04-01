import Foundation

@MainActor
final class AccountSidebarViewModel: ObservableObject {
    private static let creditCardSubtypes: Set<String> = [
        "credit",
        "credit_card"
    ]

    @Published private(set) var sections: [SidebarSectionModel] = []
    @Published private(set) var lastErrorMessage: String?
    @Published var showHiddenAccounts = false

    private let accountRepository: AccountRepository
    private let transactionRepository: TransactionRepository
    private let builder: AccountSidebarBuilder
    private let valuationService: RollupValuationService
    private var accountsByID: [Int64: Account] = [:]

    init(
        accountRepository: AccountRepository,
        transactionRepository: TransactionRepository,
        valuationService: RollupValuationService,
        builder: AccountSidebarBuilder = AccountSidebarBuilder()
    ) {
        self.accountRepository = accountRepository
        self.transactionRepository = transactionRepository
        self.valuationService = valuationService
        self.builder = builder
        self.sections = SidebarSection.allCases.map { SidebarSectionModel(section: $0, nodes: []) }
    }

    func reload() {
        do {
            let accounts = try accountRepository.getAllAccounts()
            let balancesByAccountID = try adjustedBalancesByAccountID(accounts: accounts)
            accountsByID = Dictionary(
                uniqueKeysWithValues: accounts.compactMap { account in
                    guard let accountID = account.id else {
                        return nil
                    }
                    return (accountID, account)
                }
            )
            sections = try builder.buildSections(
                from: accounts,
                balancesByAccountID: balancesByAccountID,
                valuationService: valuationService,
                showHiddenAccounts: showHiddenAccounts
            )
            lastErrorMessage = nil
        } catch {
            accountsByID = [:]
            sections = SidebarSection.allCases.map { SidebarSectionModel(section: $0, nodes: []) }
            lastErrorMessage = error.localizedDescription
        }
    }

    func account(for selection: SidebarSelection?) -> Account? {
        guard let selection else {
            return nil
        }

        guard case let .account(accountID) = selection.kind else {
            return nil
        }

        return accountsByID[accountID]
    }

    func selectionForAccount(id accountID: Int64) -> SidebarSelection? {
        guard let account = accountsByID[accountID] else {
            return nil
        }
        return SidebarSelection(
            id: "account-\(accountID)",
            title: account.name,
            kind: .account(accountID)
        )
    }

    func setShowHiddenAccounts(_ showHiddenAccounts: Bool) {
        guard self.showHiddenAccounts != showHiddenAccounts else {
            return
        }
        self.showHiddenAccounts = showHiddenAccounts
        reload()
    }

    private func adjustedBalancesByAccountID(accounts: [Account]) throws -> [Int64: Double] {
        var balancesByAccountID = try accountRepository.getAccountBalances()

        for account in accounts {
            guard let accountID = account.id,
                  account.class == "liability",
                  Self.creditCardSubtypes.contains(account.subtype) else {
                continue
            }

            let transactions = try transactionRepository.fetchTransactions(forAccountID: accountID)
            guard let effectiveUsedCredit = effectiveUsedCredit(for: account, transactions: transactions) else {
                continue
            }

            balancesByAccountID[accountID] = -effectiveUsedCredit
        }

        return balancesByAccountID
    }

    private func effectiveUsedCredit(
        for account: Account,
        transactions: [TransactionListItem]
    ) -> Double? {
        if let nextReimbursementIndex = transactions.firstIndex(where: { item in
            item.txnDate >= Self.todayDateString &&
            item.memoSummary == "Hitelkártya visszafizetés" &&
            (item.inAmount ?? 0) > 0
        }) {
            let reimbursement = transactions[nextReimbursementIndex]
            if reimbursement.state == "reconciling" || reimbursement.state == "cleared" {
                return max(0, -reimbursement.runningBalance)
            }

            if nextReimbursementIndex > 0 {
                return max(0, -transactions[nextReimbursementIndex - 1].runningBalance)
            }
        }

        if let lastTransaction = transactions.last {
            return max(0, -lastTransaction.runningBalance)
        }

        return max(0, -(account.openingBalance ?? 0))
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
