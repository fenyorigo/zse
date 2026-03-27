import Foundation

@MainActor
final class AccountDetailViewModel: ObservableObject {
    struct InlineAmountEditContext {
        let type: TransactionService.EditableTransactionType
        let counterpartAccountID: Int64
        let amount: Double
        let currency: String
    }

    struct DeleteAvailability {
        let isAllowed: Bool
        let message: String?
    }

    enum State {
        case noneSelected
        case groupingNode(String)
        case nonPostable(Account)
        case postable(Account, [TransactionListItem])
        case failed(Account?, String)
    }

    enum InspectorState {
        case empty
        case loaded(TransactionDetail)
        case failed(String)
    }

    @Published private(set) var state: State = .noneSelected
    @Published private(set) var selectedTransactionID: Int64?
    @Published private(set) var inspectorState: InspectorState = .empty
    @Published private(set) var deleteAvailability = DeleteAvailability(isAllowed: false, message: nil)
    @Published var transactionEditErrorMessage: String?

    private let accountRepository: AccountRepository
    private let transactionRepository: TransactionRepository
    private let transactionService: TransactionService

    init(
        accountRepository: AccountRepository,
        transactionRepository: TransactionRepository,
        transactionService: TransactionService
    ) {
        self.accountRepository = accountRepository
        self.transactionRepository = transactionRepository
        self.transactionService = transactionService
    }

    func setSelection(_ selection: SidebarSelection?, account: Account?) {
        clearTransactionSelection()
        deleteAvailability = DeleteAvailability(isAllowed: false, message: nil)

        guard let selection else {
            state = .noneSelected
            return
        }

        switch selection.kind {
        case .grouping, .currency:
            state = .groupingNode(selection.title)
            return
        case .account:
            break
        }

        guard let account else {
            state = .failed(nil, "The selected account could not be loaded.")
            return
        }

        updateDeleteAvailability(for: account)

        guard !isNonLeafAccount(account) else {
            state = .nonPostable(account)
            return
        }

        do {
            let transactions = try transactionRepository.fetchTransactions(forAccountID: account.id ?? 0)
            state = .postable(account, transactions)
        } catch {
            state = .failed(account, error.localizedDescription)
        }
    }

    func selectTransaction(transactionID: Int64?) {
        selectedTransactionID = transactionID
        transactionEditErrorMessage = nil

        guard let transactionID else {
            inspectorState = .empty
            return
        }

        do {
            guard let detail = try transactionRepository.fetchTransactionDetail(transactionID: transactionID) else {
                inspectorState = .failed("The selected transaction could not be loaded.")
                return
            }
            inspectorState = .loaded(detail)
        } catch {
            inspectorState = .failed(error.localizedDescription)
        }
    }

    private func clearTransactionSelection() {
        selectedTransactionID = nil
        inspectorState = .empty
        transactionEditErrorMessage = nil
    }

    var currentPostableAccount: Account? {
        guard case let .postable(account, _) = state else {
            return nil
        }
        return account
    }

    var currentPostableTransactions: [TransactionListItem] {
        guard case let .postable(_, transactions) = state else {
            return []
        }
        return transactions
    }

    func reloadCurrentAccount(selecting transactionID: Int64? = nil) {
        guard let currentAccount = currentPostableAccount else {
            return
        }

        do {
            let transactions = try transactionRepository.fetchTransactions(forAccountID: currentAccount.id ?? 0)
            state = .postable(currentAccount, transactions)
            selectTransaction(transactionID: transactionID)
        } catch {
            state = .failed(currentAccount, error.localizedDescription)
        }
    }

    var currentTransactionDetail: TransactionDetail? {
        guard case let .loaded(detail) = inspectorState else {
            return nil
        }
        return detail
    }

    func updateSelectedTransactionState(_ state: String) {
        guard let detail = currentTransactionDetail else {
            return
        }

        do {
            try transactionService.changeTransactionState(transactionID: detail.id, state: state)
            try reloadTransactionSelection(transactionID: detail.id)
            transactionEditErrorMessage = nil
        } catch {
            transactionEditErrorMessage = error.localizedDescription
        }
    }

    func updateSelectedTransactionDate(_ date: Date) {
        guard let detail = currentTransactionDetail else {
            return
        }

        do {
            try transactionService.updateTransactionHeader(
                transactionID: detail.id,
                txnDate: Self.dateFormatter.string(from: date),
                description: detail.description,
                state: detail.state
            )
            try reloadTransactionSelection(transactionID: detail.id)
            transactionEditErrorMessage = nil
        } catch {
            transactionEditErrorMessage = error.localizedDescription
        }
    }

    func updateSelectedTransaction(
        txnDate: String,
        description: String?,
        state: String,
        type: TransactionService.EditableTransactionType,
        counterpartAccountID: Int64?,
        currentAmount: Double?,
        counterpartAmount: Double?
    ) throws {
        guard let detail = currentTransactionDetail else {
            throw PersistenceError.transactionNotFound(-1)
        }

            if let counterpartAccountID {
                guard let currentAccount = currentPostableAccount, let currentAccountID = currentAccount.id else {
                    throw PersistenceError.transactionNotFound(-1)
                }

                try transactionService.updateSimpleTransaction(
                    transactionID: detail.id,
                    currentAccountID: currentAccountID,
                    counterpartAccountID: counterpartAccountID,
                    type: type,
                    currentAmount: currentAmount,
                    counterpartAmount: counterpartAmount,
                    txnDate: txnDate,
                    description: description,
                    state: state
                )
        } else {
            try transactionService.updateTransactionHeader(
                transactionID: detail.id,
                txnDate: txnDate,
                description: description,
                state: state
            )
        }

        try reloadTransactionSelection(transactionID: detail.id)
        transactionEditErrorMessage = nil
    }

    func inlineAmountEditContext() -> InlineAmountEditContext? {
        guard let detail = currentTransactionDetail,
              let currentAccount = currentPostableAccount,
              currentAccount.class == "asset" || currentAccount.class == "liability",
              let type = editableTransactionType(),
              let counterpartAccountID = selectedCounterpartAccountIDForEdit() else {
            return nil
        }

        guard detail.entries.count == 2 else {
            return nil
        }

        let currencies = Set(detail.entries.map(\.currency))
        guard currencies.count == 1 else {
            return nil
        }

        return InlineAmountEditContext(
            type: type,
            counterpartAccountID: counterpartAccountID,
            amount: currentAmountForEdit(),
            currency: currentAccount.currency
        )
    }

    func updateSelectedTransactionAmount(_ amount: Double) throws {
        guard let detail = currentTransactionDetail,
              let context = inlineAmountEditContext() else {
            throw TransactionServiceError.unsupportedTransactionEdit
        }

        try updateSelectedTransaction(
            txnDate: detail.txnDate,
            description: detail.description,
            state: detail.state,
            type: context.type,
            counterpartAccountID: context.counterpartAccountID,
            currentAmount: amount,
            counterpartAmount: amount
        )
    }

    func editableTransactionType() -> TransactionService.EditableTransactionType? {
        guard let currentAccount = currentPostableAccount,
              let currentAccountID = currentAccount.id else {
            return nil
        }

        guard currentAccount.class == "asset" || currentAccount.class == "liability" else {
            return nil
        }

        guard let detail = currentTransactionDetail else {
            return nil
        }

        guard detail.entries.count == 2,
              let currentEntry = detail.entries.first(where: { $0.accountID == currentAccountID }),
              let counterpartEntry = detail.entries.first(where: { $0.accountID != currentAccountID }) else {
            return nil
        }

        do {
            guard let counterpartAccount = try accountRepository.getAccount(id: counterpartEntry.accountID) else {
                return nil
            }

            if counterpartAccount.class == "income" && currentEntry.amount > 0 {
                return .deposit
            }
            if counterpartAccount.class == "expense" && currentEntry.amount < 0 {
                return .spending
            }

            if (counterpartAccount.class == "asset" || counterpartAccount.class == "liability") {
                return .transfer
            }

            return .transfer
        } catch {
            transactionEditErrorMessage = error.localizedDescription
            return nil
        }
    }

    func editableIncomeOptions() -> [EditTransactionViewModel.CounterpartOption] {
        editableCounterpartOptions(for: ["income"])
    }

    func editableExpenseOptions() -> [EditTransactionViewModel.CounterpartOption] {
        editableCounterpartOptions(for: ["expense"])
    }

    func editableTransferOptions() -> [EditTransactionViewModel.CounterpartOption] {
        editableCounterpartOptions(for: ["asset", "liability"])
    }

    func selectedCounterpartAccountIDForEdit() -> Int64? {
        guard let currentAccount = currentPostableAccount,
              let currentAccountID = currentAccount.id,
              let detail = currentTransactionDetail else {
            return nil
        }

        guard detail.entries.count == 2 else {
            return nil
        }
        guard let counterpartEntry = detail.entries.first(where: { $0.accountID != currentAccountID }) else {
            return nil
        }

        return counterpartEntry.accountID
    }

    func currentAmountForEdit() -> Double {
        guard let currentAccount = currentPostableAccount,
              let currentAccountID = currentAccount.id,
              let detail = currentTransactionDetail,
              let currentEntry = detail.entries.first(where: { $0.accountID == currentAccountID }) else {
            return 0
        }
        return abs(currentEntry.amount)
    }

    func counterpartAmountForEdit() -> Double {
        guard let currentAccount = currentPostableAccount,
              let currentAccountID = currentAccount.id,
              let detail = currentTransactionDetail,
              let counterpartEntry = detail.entries.first(where: { $0.accountID != currentAccountID }) else {
            return 0
        }
        return abs(counterpartEntry.amount)
    }

    func deleteSelectedTransaction() throws {
        guard let detail = currentTransactionDetail else {
            throw PersistenceError.transactionNotFound(-1)
        }

        try transactionService.deleteTransaction(transactionID: detail.id)
        clearTransactionSelection()
        reloadCurrentAccount()
    }

    func updateTransactionDates(transactionIDs: Set<Int64>, to date: Date) throws {
        let txnDate = Self.dateFormatter.string(from: date)
        let sortedTransactionIDs = transactionIDs.sorted()

        try transactionRepository.writeInTransaction { db in
            for transactionID in sortedTransactionIDs {
                guard let detail = try transactionRepository.fetchTransactionDetail(
                    transactionID: transactionID,
                    db: db
                ) else {
                    throw PersistenceError.transactionNotFound(transactionID)
                }

                try transactionRepository.updateTransaction(
                    id: transactionID,
                    txnDate: txnDate,
                    description: detail.description,
                    state: detail.state,
                    db: db
                )
            }
        }

        transactionEditErrorMessage = nil
        reloadCurrentAccount()
    }

    func updateTransactionStates(transactionIDs: Set<Int64>, to state: String) throws {
        let sortedTransactionIDs = transactionIDs.sorted()

        for transactionID in sortedTransactionIDs {
            try transactionService.changeTransactionState(transactionID: transactionID, state: state)
        }

        transactionEditErrorMessage = nil
        reloadCurrentAccount()
    }

    func deleteTransactions(transactionIDs: Set<Int64>) throws {
        let sortedTransactionIDs = transactionIDs.sorted()

        try transactionRepository.writeInTransaction { db in
            for transactionID in sortedTransactionIDs {
                guard let detail = try transactionRepository.fetchTransactionDetail(
                    transactionID: transactionID,
                    db: db
                ) else {
                    throw PersistenceError.transactionNotFound(transactionID)
                }

                guard detail.state == "uncleared" else {
                    throw TransactionServiceError.onlyUnclearedTransactionsCanBeDeleted
                }
            }

            for transactionID in sortedTransactionIDs {
                try transactionRepository.deleteTransaction(id: transactionID, db: db)
            }
        }

        clearTransactionSelection()
        reloadCurrentAccount()
    }

    func duplicateTransaction(transactionID: Int64) throws -> Int64 {
        let transaction = try transactionService.duplicateTransaction(transactionID: transactionID)
        let newTransactionID = transaction.id ?? 0
        reloadCurrentAccount(selecting: newTransactionID)
        return newTransactionID
    }

    func deleteTransaction(transactionID: Int64) throws {
        try transactionService.deleteTransaction(transactionID: transactionID)

        if selectedTransactionID == transactionID {
            clearTransactionSelection()
        }

        reloadCurrentAccount()
    }

    var currentSelectedAccount: Account? {
        switch state {
        case .nonPostable(let account):
            return account
        case .postable(let account, _):
            return account
        case .failed(let account, _):
            return account
        case .noneSelected, .groupingNode:
            return nil
        }
    }

    func deleteSelectedAccount() throws {
        guard let account = currentSelectedAccount, let accountID = account.id else {
            throw AccountDeletionError.noAccountSelected
        }

        updateDeleteAvailability(for: account)

        guard deleteAvailability.isAllowed else {
            throw AccountDeletionError.notAllowed(deleteAvailability.message ?? "This account cannot be deleted.")
        }

        try accountRepository.deleteAccount(id: accountID)
        state = .noneSelected
        clearTransactionSelection()
        deleteAvailability = DeleteAvailability(isAllowed: false, message: nil)
    }

    private func updateDeleteAvailability(for account: Account) {
        guard let accountID = account.id else {
            deleteAvailability = DeleteAvailability(
                isAllowed: false,
                message: "The selected account is missing an identifier."
            )
            return
        }

        do {
            if try accountRepository.hasChildren(accountID: accountID) {
                deleteAvailability = DeleteAvailability(
                    isAllowed: false,
                    message: "Accounts with child accounts cannot be deleted."
                )
                return
            }

            if try transactionRepository.hasEntries(forAccountID: accountID) {
                deleteAvailability = DeleteAvailability(
                    isAllowed: false,
                    message: "Accounts with transactions cannot be deleted."
                )
                return
            }

            deleteAvailability = DeleteAvailability(isAllowed: true, message: nil)
        } catch {
            deleteAvailability = DeleteAvailability(isAllowed: false, message: error.localizedDescription)
        }
    }

    private func isNonLeafAccount(_ account: Account) -> Bool {
        guard let accountID = account.id else {
            return true
        }

        if account.isGroup {
            return true
        }

        do {
            return try accountRepository.hasChildren(accountID: accountID)
        } catch {
            return true
        }
    }

    private func reloadTransactionSelection(transactionID: Int64) throws {
        guard let currentAccount = currentPostableAccount else {
            return
        }

        let transactions = try transactionRepository.fetchTransactions(forAccountID: currentAccount.id ?? 0)
        state = .postable(currentAccount, transactions)
        selectedTransactionID = transactionID

        guard let detail = try transactionRepository.fetchTransactionDetail(transactionID: transactionID) else {
            inspectorState = .empty
            return
        }

        inspectorState = .loaded(detail)
    }

    private func editableCounterpartOptions(for classes: Set<String>) -> [EditTransactionViewModel.CounterpartOption] {
        guard let currentAccount = currentPostableAccount,
              let currentAccountID = currentAccount.id else {
            return []
        }

        guard currentAccount.class == "asset" || currentAccount.class == "liability" else {
            return []
        }

        guard let detail = currentTransactionDetail,
              detail.entries.count == 2,
              detail.entries.contains(where: { $0.accountID == currentAccountID }) else {
            return []
        }

        do {
            let allAccounts = try accountRepository.getAllAccounts()
            let leafAccounts = try accountRepository.getLeafAccounts()
            let accountsByID: [Int64: Account] = Dictionary(
                uniqueKeysWithValues: allAccounts.compactMap { account in
                    guard let accountID = account.id else {
                        return nil
                    }
                    return (accountID, account)
                }
            )

            return leafAccounts.compactMap { account in
                guard let accountID = account.id else {
                    return nil
                }

                guard accountID != currentAccountID else {
                    return nil
                }

                guard classes.contains(account.class) else {
                    return nil
                }

                if account.class == "income" || account.class == "expense" {
                    guard account.currency == currentAccount.currency else {
                        return nil
                    }
                }

                return EditTransactionViewModel.CounterpartOption(
                    id: accountID,
                    fullPath: accountPath(for: account, accountsByID: accountsByID),
                    accountClass: account.class,
                    currency: account.currency
                )
            }
            .sorted { left, right in
                left.fullPath.localizedCaseInsensitiveCompare(right.fullPath) == .orderedAscending
            }
        } catch {
            transactionEditErrorMessage = error.localizedDescription
            return []
        }
    }

    func currentAccountNameForEdit() -> String {
        currentPostableAccount?.name ?? "Current Account"
    }

    func currentAccountCurrencyForEdit() -> String {
        currentPostableAccount?.currency ?? ""
    }

    private func accountPath(
        for account: Account,
        accountsByID: [Int64: Account]
    ) -> String {
        var components = [account.name]
        var currentParentID = account.parentID

        while let parentID = currentParentID,
              let parentAccount = accountsByID[parentID] {
            components.append(parentAccount.name)
            currentParentID = parentAccount.parentID
        }

        return components.reversed().joined(separator: " / ")
    }
}

extension AccountDetailViewModel {
    fileprivate static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

enum AccountDeletionError: Error, LocalizedError {
    case noAccountSelected
    case notAllowed(String)

    var errorDescription: String? {
        switch self {
        case .noAccountSelected:
            return "No account is selected."
        case .notAllowed(let message):
            return message
        }
    }
}
