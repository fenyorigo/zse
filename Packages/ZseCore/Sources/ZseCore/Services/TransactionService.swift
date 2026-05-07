import Foundation
import GRDB

struct TransactionService {
    enum EditableTransactionType: String, CaseIterable, Identifiable {
        case deposit
        case spending
        case transfer

        var id: String { rawValue }
    }

    private let accountRepository: AccountRepository
    private let partnerRepository: PartnerRepository
    private let transactionRepository: TransactionRepository
    private let balanceTolerance = 0.000001
    private let allowedStates: Set<String> = ["uncleared", "reconciling", "cleared"]

    init(
        accountRepository: AccountRepository,
        partnerRepository: PartnerRepository,
        transactionRepository: TransactionRepository
    ) {
        self.accountRepository = accountRepository
        self.partnerRepository = partnerRepository
        self.transactionRepository = transactionRepository
    }

    // MARK: - Generic Creation

    @discardableResult
    func createTransaction(
        txnDate: String,
        description: String?,
        state: String,
        statusWarningFlag: Bool = false,
        statusWarningReason: String? = nil,
        entries: [EntryInput]
    ) throws -> Transaction {
        try transactionRepository.writeInTransaction { db in
            try validate(entries: entries, state: state, db: db)

            var transaction = Transaction(
                txnDate: txnDate,
                description: description,
                state: state,
                statusWarningFlag: statusWarningFlag,
                statusWarningReason: statusWarningReason
            )

            var domainEntries = entries.map {
                Entry(
                    accountID: $0.accountID,
                    amount: $0.amount,
                    currency: $0.currency,
                    partnerID: $0.partnerID,
                    memo: $0.memo
                )
            }

            try transactionRepository.createTransaction(&transaction, entries: &domainEntries, db: db)
            return transaction
        }
    }

    // MARK: - Edit

    func updateSimpleTransaction(
        transactionID: Int64,
        currentAccountID: Int64,
        counterpartAccountID: Int64,
        type: EditableTransactionType,
        currentAmount: Double?,
        counterpartAmount: Double?,
        txnDate: String,
        description: String?,
        state: String
    ) throws {
        try transactionRepository.writeInTransaction { db in
            let existingTransaction = try requireTransaction(transactionID: transactionID, db: db)
            _ = try requirePostableLeafAccount(id: currentAccountID, db: db)
            let counterpartAccount = try requirePostableLeafAccount(id: counterpartAccountID, db: db)

            let entries = try transactionRepository.fetchEntries(for: transactionID, db: db)
            guard entries.count == 2 else {
                throw TransactionServiceError.unsupportedTransactionEdit
            }

            let matchingCurrentEntries = entries.filter { $0.accountID == currentAccountID }
            guard matchingCurrentEntries.count == 1,
                  let currentEntry = matchingCurrentEntries.first else {
                throw TransactionServiceError.transactionDoesNotBelongToSelectedAccount
            }

            guard let counterpartEntry = entries.first(where: { $0.id != currentEntry.id }) else {
                throw TransactionServiceError.unsupportedTransactionEdit
            }

            guard currentEntry.accountID != counterpartAccountID else {
                throw TransactionServiceError.duplicateAccounts
            }

            let resolvedCurrentAmount = try requirePositiveAmount(
                currentAmount,
                missingError: .missingAmountForTransactionType(type)
            )

            var updatedCurrentEntry = currentEntry
            var updatedCounterpartEntry = counterpartEntry
            updatedCounterpartEntry.accountID = counterpartAccountID
            updatedCounterpartEntry.currency = counterpartAccount.currency

            switch type {
            case .deposit:
                guard counterpartAccount.class == "income" else {
                    throw TransactionServiceError.invalidCounterpartClass(
                        expected: "income",
                        actual: counterpartAccount.class
                    )
                }

                guard currentEntry.currency == counterpartAccount.currency else {
                    throw TransactionServiceError.accountCurrencyMismatch(
                        accountID: counterpartAccountID,
                        accountCurrency: counterpartAccount.currency,
                        entryCurrency: currentEntry.currency
                    )
                }

                updatedCurrentEntry.amount = resolvedCurrentAmount
                updatedCounterpartEntry.amount = -resolvedCurrentAmount
            case .spending:
                guard counterpartAccount.class == "expense" else {
                    throw TransactionServiceError.invalidCounterpartClass(
                        expected: "expense",
                        actual: counterpartAccount.class
                    )
                }

                guard currentEntry.currency == counterpartAccount.currency else {
                    throw TransactionServiceError.accountCurrencyMismatch(
                        accountID: counterpartAccountID,
                        accountCurrency: counterpartAccount.currency,
                        entryCurrency: currentEntry.currency
                    )
                }

                updatedCurrentEntry.amount = -resolvedCurrentAmount
                updatedCounterpartEntry.amount = resolvedCurrentAmount
            case .transfer:
                guard counterpartAccount.class == "asset" || counterpartAccount.class == "liability" else {
                    throw TransactionServiceError.invalidCounterpartClass(
                        expected: "asset or liability",
                        actual: counterpartAccount.class
                    )
                }

                let counterpartMagnitude: Double
                if currentEntry.currency == counterpartAccount.currency {
                    counterpartMagnitude = resolvedCurrentAmount
                    if let counterpartAmount,
                       abs(counterpartAmount - resolvedCurrentAmount) > balanceTolerance {
                        throw TransactionServiceError.sameCurrencyTransferAmountMismatch
                    }
                } else {
                    counterpartMagnitude = try requirePositiveAmount(
                        counterpartAmount,
                        missingError: .missingTargetAmountForCrossCurrencyTransfer
                    )
                }

                let currentSign = currentEntry.amount >= 0 ? 1.0 : -1.0
                updatedCurrentEntry.amount = currentSign * resolvedCurrentAmount
                updatedCounterpartEntry.amount = -currentSign * counterpartMagnitude
            }

            try validate(
                entries: [
                    EntryInput(
                        accountID: updatedCurrentEntry.accountID,
                        amount: updatedCurrentEntry.amount,
                        currency: updatedCurrentEntry.currency,
                        partnerID: updatedCurrentEntry.partnerID,
                        memo: updatedCurrentEntry.memo
                    ),
                    EntryInput(
                        accountID: updatedCounterpartEntry.accountID,
                        amount: updatedCounterpartEntry.amount,
                        currency: updatedCounterpartEntry.currency,
                        partnerID: updatedCounterpartEntry.partnerID,
                        memo: updatedCounterpartEntry.memo
                    )
                ],
                state: state,
                db: db
            )

            try transactionRepository.updateTransaction(
                id: transactionID,
                txnDate: txnDate,
                description: description,
                state: state,
                entries: [updatedCurrentEntry, updatedCounterpartEntry],
                db: db
            )
            try clearStatusWarningIfNeeded(
                transactionID: transactionID,
                previousDate: existingTransaction.txnDate,
                previousState: existingTransaction.state,
                newDate: txnDate,
                newState: state,
                existingWarningReason: existingTransaction.statusWarningReason,
                db: db
            )
        }
    }

    // MARK: - Delete & Duplicate

    func deleteTransaction(transactionID: Int64) throws {
        try transactionRepository.writeInTransaction { db in
            guard let detail = try transactionRepository.fetchTransactionDetail(
                transactionID: transactionID,
                db: db
            ) else {
                throw PersistenceError.transactionNotFound(transactionID)
            }

            guard detail.state == "uncleared" else {
                throw TransactionServiceError.onlyUnclearedTransactionsCanBeDeleted
            }

            try transactionRepository.deleteTransaction(id: transactionID, db: db)
        }
    }

    @discardableResult
    func duplicateTransaction(transactionID: Int64) throws -> Transaction {
        try transactionRepository.writeInTransaction { db in
            let originalTransaction = try requireTransaction(transactionID: transactionID, db: db)
            let originalEntries = try transactionRepository.fetchEntries(for: transactionID, db: db)

            guard originalEntries.count >= 2 else {
                throw TransactionServiceError.notEnoughEntries
            }

            let duplicatedInputs = originalEntries.map {
                EntryInput(
                    accountID: $0.accountID,
                    amount: $0.amount,
                    currency: $0.currency,
                    partnerID: $0.partnerID,
                    memo: $0.memo
                )
            }

            try validate(entries: duplicatedInputs, state: "uncleared", db: db)

            var duplicatedTransaction = Transaction(
                txnDate: originalTransaction.txnDate,
                description: originalTransaction.description,
                state: "uncleared"
            )

            var duplicatedEntries = duplicatedInputs.map {
                Entry(
                    accountID: $0.accountID,
                    amount: $0.amount,
                    currency: $0.currency,
                    partnerID: $0.partnerID,
                    memo: $0.memo
                )
            }

            try transactionRepository.createTransaction(
                &duplicatedTransaction,
                entries: &duplicatedEntries,
                db: db
            )

            return duplicatedTransaction
        }
    }

    func changeTransactionState(transactionID: Int64, state: String) throws {
        try transactionRepository.writeInTransaction { db in
            let transaction = try requireTransaction(transactionID: transactionID, db: db)
            try updateTransactionHeader(
                transactionID: transactionID,
                txnDate: transaction.txnDate,
                description: transaction.description,
                state: state,
                db: db
            )
            try clearStatusWarningIfNeeded(
                transactionID: transactionID,
                previousDate: transaction.txnDate,
                previousState: transaction.state,
                newDate: transaction.txnDate,
                newState: state,
                existingWarningReason: transaction.statusWarningReason,
                db: db
            )
        }
    }

    func updateTransactionHeader(
        transactionID: Int64,
        txnDate: String,
        description: String?,
        state: String
    ) throws {
        try transactionRepository.writeInTransaction { db in
            try updateTransactionHeader(
                transactionID: transactionID,
                txnDate: txnDate,
                description: description,
                state: state,
                db: db
            )
        }
    }

    // MARK: - Typed Creation

    @discardableResult
    func createDeposit(
        currentAccountID: Int64,
        incomeCategoryAccountID: Int64,
        date: String,
        description: String?,
        state: String,
        amount: Double,
        partnerName: String?,
        memo: String?
    ) throws -> Transaction {
        try transactionRepository.writeInTransaction { db in
            try createDeposit(
                currentAccountID: currentAccountID,
                incomeCategoryAccountID: incomeCategoryAccountID,
                date: date,
                description: description,
                state: state,
                amount: amount,
                partnerName: partnerName,
                memo: memo,
                db: db
            )
        }
    }

    @discardableResult
    func createDeposit(
        currentAccountID: Int64,
        incomeCategoryAccountID: Int64,
        date: String,
        description: String?,
        state: String,
        amount: Double,
        partnerName: String?,
        memo: String?,
        db: Database
    ) throws -> Transaction {
            let currentAccount = try requirePostableLeafAccount(id: currentAccountID, db: db)
            let incomeAccount = try requirePostableLeafAccount(id: incomeCategoryAccountID, db: db)

            guard incomeAccount.class == "income" else {
                throw TransactionServiceError.invalidCounterpartClass(
                    expected: "income",
                    actual: incomeAccount.class
                )
            }

            let partnerID = try resolvePartnerID(from: partnerName, db: db)

            return try createTwoEntryTransaction(
                date: date,
                description: description,
                state: state,
                positiveAccountID: currentAccountID,
                positiveCurrency: currentAccount.currency,
                positiveAmount: amount,
                negativeAccountID: incomeCategoryAccountID,
                negativeCurrency: currentAccount.currency,
                negativeAmount: amount,
                partnerID: partnerID,
                memo: memo,
                db: db
            )
    }

    @discardableResult
    func createSpending(
        currentAccountID: Int64,
        expenseCategoryAccountID: Int64,
        date: String,
        description: String?,
        state: String,
        amount: Double,
        partnerName: String?,
        memo: String?
    ) throws -> Transaction {
        try transactionRepository.writeInTransaction { db in
            try createSpending(
                currentAccountID: currentAccountID,
                expenseCategoryAccountID: expenseCategoryAccountID,
                date: date,
                description: description,
                state: state,
                amount: amount,
                partnerName: partnerName,
                memo: memo,
                db: db
            )
        }
    }

    @discardableResult
    func createSpending(
        currentAccountID: Int64,
        expenseCategoryAccountID: Int64,
        date: String,
        description: String?,
        state: String,
        amount: Double,
        partnerName: String?,
        memo: String?,
        db: Database
    ) throws -> Transaction {
            let currentAccount = try requirePostableLeafAccount(id: currentAccountID, db: db)
            let expenseAccount = try requirePostableLeafAccount(id: expenseCategoryAccountID, db: db)

            guard expenseAccount.class == "expense" else {
                throw TransactionServiceError.invalidCounterpartClass(
                    expected: "expense",
                    actual: expenseAccount.class
                )
            }

            let partnerID = try resolvePartnerID(from: partnerName, db: db)

            return try createTwoEntryTransaction(
                date: date,
                description: description,
                state: state,
                positiveAccountID: expenseCategoryAccountID,
                positiveCurrency: currentAccount.currency,
                positiveAmount: amount,
                negativeAccountID: currentAccountID,
                negativeCurrency: currentAccount.currency,
                negativeAmount: amount,
                partnerID: partnerID,
                memo: memo,
                db: db
            )
    }

    @discardableResult
    func createCategorizedPosting(
        currentAccountID: Int64,
        categoryAccountID: Int64,
        currentSignedAmount: Double,
        date: String,
        description: String?,
        state: String,
        statusWarningFlag: Bool = false,
        statusWarningReason: String? = nil,
        partnerName: String?,
        memo: String?,
        db: Database
    ) throws -> Transaction {
            guard currentSignedAmount != 0 else {
                throw TransactionServiceError.invalidAmount(currentSignedAmount)
            }

            let currentAccount = try requirePostableLeafAccount(id: currentAccountID, db: db)
            let categoryAccount = try requirePostableLeafAccount(id: categoryAccountID, db: db)

            guard categoryAccount.class == "income" || categoryAccount.class == "expense" else {
                throw TransactionServiceError.invalidCounterpartClass(
                    expected: "income or expense",
                    actual: categoryAccount.class
                )
            }

            let partnerID = try resolvePartnerID(from: partnerName, db: db)
            let amount = abs(currentSignedAmount)

            if currentSignedAmount > 0 {
                return try createTwoEntryTransaction(
                    date: date,
                    description: description,
                    state: state,
                    statusWarningFlag: statusWarningFlag,
                    statusWarningReason: statusWarningReason,
                    positiveAccountID: currentAccountID,
                    positiveCurrency: currentAccount.currency,
                    positiveAmount: amount,
                    negativeAccountID: categoryAccountID,
                    negativeCurrency: currentAccount.currency,
                    negativeAmount: amount,
                    partnerID: partnerID,
                    memo: memo,
                    db: db
                )
            }

            return try createTwoEntryTransaction(
                date: date,
                description: description,
                state: state,
                statusWarningFlag: statusWarningFlag,
                statusWarningReason: statusWarningReason,
                positiveAccountID: categoryAccountID,
                positiveCurrency: currentAccount.currency,
                positiveAmount: amount,
                negativeAccountID: currentAccountID,
                negativeCurrency: currentAccount.currency,
                negativeAmount: amount,
                partnerID: partnerID,
                memo: memo,
                db: db
            )
    }

    @discardableResult
    func createTransfer(
        sourceAccountID: Int64,
        targetAccountID: Int64,
        sourceAmount: Double,
        targetAmount: Double?,
        date: String,
        description: String?,
        state: String,
        statusWarningFlag: Bool = false,
        statusWarningReason: String? = nil,
        partnerName: String?,
        memo: String?
    ) throws -> Transaction {
        try transactionRepository.writeInTransaction { db in
            try createTransfer(
                sourceAccountID: sourceAccountID,
                targetAccountID: targetAccountID,
                sourceAmount: sourceAmount,
                targetAmount: targetAmount,
                date: date,
                description: description,
                state: state,
                statusWarningFlag: statusWarningFlag,
                statusWarningReason: statusWarningReason,
                partnerName: partnerName,
                memo: memo,
                db: db
            )
        }
    }

    @discardableResult
    func createTransfer(
        sourceAccountID: Int64,
        targetAccountID: Int64,
        sourceAmount: Double,
        targetAmount: Double?,
        date: String,
        description: String?,
        state: String,
        statusWarningFlag: Bool = false,
        statusWarningReason: String? = nil,
        partnerName: String?,
        memo: String?,
        db: Database
    ) throws -> Transaction {
            guard sourceAccountID != targetAccountID else {
                throw TransactionServiceError.duplicateAccounts
            }

            guard sourceAmount > 0 else {
                throw TransactionServiceError.invalidAmount(sourceAmount)
            }

            let sourceAccount = try requirePostableLeafAccount(id: sourceAccountID, db: db)
            let targetAccount = try requirePostableLeafAccount(id: targetAccountID, db: db)
            let partnerID = try resolvePartnerID(from: partnerName, db: db)

            if sourceAccount.currency == targetAccount.currency {
                let resolvedTargetAmount = targetAmount ?? sourceAmount

                guard abs(resolvedTargetAmount - sourceAmount) <= balanceTolerance else {
                    throw TransactionServiceError.sameCurrencyTransferAmountMismatch
                }

                return try createTwoEntryTransaction(
                    date: date,
                    description: description,
                    state: state,
                    statusWarningFlag: statusWarningFlag,
                    statusWarningReason: statusWarningReason,
                    positiveAccountID: targetAccountID,
                    positiveCurrency: targetAccount.currency,
                    positiveAmount: resolvedTargetAmount,
                    negativeAccountID: sourceAccountID,
                    negativeCurrency: sourceAccount.currency,
                    negativeAmount: sourceAmount,
                    partnerID: partnerID,
                    memo: memo,
                    db: db
                )
            }

            guard let targetAmount, targetAmount > 0 else {
                throw TransactionServiceError.missingTargetAmountForCrossCurrencyTransfer
            }

            return try createTwoEntryTransaction(
                date: date,
                description: description,
                state: state,
                statusWarningFlag: statusWarningFlag,
                statusWarningReason: statusWarningReason,
                positiveAccountID: targetAccountID,
                positiveCurrency: targetAccount.currency,
                positiveAmount: targetAmount,
                negativeAccountID: sourceAccountID,
                negativeCurrency: sourceAccount.currency,
                negativeAmount: sourceAmount,
                partnerID: partnerID,
                memo: memo,
                db: db
            )
    }

    // MARK: - Private Helpers

    @discardableResult
    private func createTwoEntryTransaction(
        date: String,
        description: String?,
        state: String,
        statusWarningFlag: Bool = false,
        statusWarningReason: String? = nil,
        positiveAccountID: Int64,
        positiveCurrency: String,
        positiveAmount: Double,
        negativeAccountID: Int64,
        negativeCurrency: String,
        negativeAmount: Double,
        partnerID: Int64?,
        memo: String?,
        db: Database
    ) throws -> Transaction {
        guard positiveAmount > 0 else {
            throw TransactionServiceError.invalidAmount(positiveAmount)
        }

        guard negativeAmount > 0 else {
            throw TransactionServiceError.invalidAmount(negativeAmount)
        }

        guard positiveAccountID != negativeAccountID else {
            throw TransactionServiceError.duplicateAccounts
        }

        let entryInputs = [
            EntryInput(
                accountID: positiveAccountID,
                amount: positiveAmount,
                currency: positiveCurrency,
                partnerID: partnerID,
                memo: memo
            ),
            EntryInput(
                accountID: negativeAccountID,
                amount: -negativeAmount,
                currency: negativeCurrency,
                partnerID: partnerID,
                memo: memo
            )
        ]

        try validate(entries: entryInputs, state: state, db: db)

        var transaction = Transaction(
            txnDate: date,
            description: description,
            state: state,
            statusWarningFlag: statusWarningFlag,
            statusWarningReason: statusWarningReason
        )

        var entries = entryInputs.map {
            Entry(
                accountID: $0.accountID,
                amount: $0.amount,
                currency: $0.currency,
                partnerID: $0.partnerID,
                memo: $0.memo
            )
        }

        try transactionRepository.createTransaction(&transaction, entries: &entries, db: db)
        return transaction
    }

    private func requirePostableLeafAccount(id: Int64, db: Database) throws -> Account {
        guard let account = try accountRepository.getAccount(id: id, db: db) else {
            throw TransactionServiceError.accountNotFound(id)
        }

        guard !account.isGroup else {
            throw TransactionServiceError.groupAccountNotPostable(id)
        }

        let isCategoryAccount = account.class == "income" || account.class == "expense"
        let hasChildren = try accountRepository.hasChildren(accountID: id, db: db)

        guard isCategoryAccount || !hasChildren else {
            throw TransactionServiceError.nonLeafAccountNotPostable(id)
        }

        return account
    }

    private func validate(entries: [EntryInput], state: String, db: Database) throws {
        guard allowedStates.contains(state) else {
            throw TransactionServiceError.invalidState(state)
        }

        guard entries.count >= 2 else {
            throw TransactionServiceError.notEnoughEntries
        }

        for entry in entries {
            guard let account = try accountRepository.getAccount(id: entry.accountID, db: db) else {
                throw TransactionServiceError.accountNotFound(entry.accountID)
            }

            guard !account.isGroup else {
                throw TransactionServiceError.groupAccountNotPostable(entry.accountID)
            }

            let isCategoryAccount = account.class == "income" || account.class == "expense"
            let hasChildren = try accountRepository.hasChildren(accountID: entry.accountID, db: db)

            guard isCategoryAccount || !hasChildren else {
                throw TransactionServiceError.nonLeafAccountNotPostable(entry.accountID)
            }

            guard isCategoryAccount || account.currency == entry.currency else {
                throw TransactionServiceError.accountCurrencyMismatch(
                    accountID: entry.accountID,
                    accountCurrency: account.currency,
                    entryCurrency: entry.currency
                )
            }
        }

        let currencies = Set(entries.map(\.currency))
        if currencies.count == 1 {
            let total = entries.reduce(0.0) { partialResult, entry in
                partialResult + entry.amount
            }

            guard abs(total) <= balanceTolerance else {
                throw TransactionServiceError.unbalancedEntries(total)
            }
            return
        }

        guard entries.count == 2 else {
            throw TransactionServiceError.crossCurrencyRequiresExactlyTwoEntries
        }
    }

    private func resolvePartnerID(from partnerName: String?, db: Database) throws -> Int64? {
        guard let partnerName else {
            return nil
        }

        let trimmedName = partnerName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            return nil
        }

        if let existingPartner = try partnerRepository.findPartner(named: trimmedName, db: db) {
            return existingPartner.id
        }

        var partner = Partner(name: trimmedName)
        try partnerRepository.createPartner(&partner, db: db)
        return partner.id
    }

    private func requireTransaction(transactionID: Int64, db: Database) throws -> Transaction {
        guard let transaction = try Transaction.fetchOne(db, key: transactionID) else {
            throw PersistenceError.transactionNotFound(transactionID)
        }

        return transaction
    }

    private func updateTransactionHeader(
        transactionID: Int64,
        txnDate: String,
        description: String?,
        state: String,
        db: Database
    ) throws {
        let existingTransaction = try requireTransaction(transactionID: transactionID, db: db)

        guard allowedStates.contains(state) else {
            throw TransactionServiceError.invalidState(state)
        }

        let entries = try transactionRepository.fetchEntries(for: transactionID, db: db)
        let entryInputs = entries.map {
            EntryInput(
                accountID: $0.accountID,
                amount: $0.amount,
                currency: $0.currency,
                partnerID: $0.partnerID,
                memo: $0.memo
            )
        }

        try validate(entries: entryInputs, state: state, db: db)
        try transactionRepository.updateTransaction(
            id: transactionID,
            txnDate: txnDate,
            description: description,
            state: state,
            db: db
        )
        try clearStatusWarningIfNeeded(
            transactionID: transactionID,
            previousDate: existingTransaction.txnDate,
            previousState: existingTransaction.state,
            newDate: txnDate,
            newState: state,
            existingWarningReason: existingTransaction.statusWarningReason,
            db: db
        )
    }

    private func clearStatusWarningIfNeeded(
        transactionID: Int64,
        previousDate: String,
        previousState: String,
        newDate: String,
        newState: String,
        existingWarningReason: String?,
        db: Database
    ) throws {
        if previousState != newState {
            try transactionRepository.clearStatusWarning(transactionID: transactionID, db: db)
            return
        }

        guard previousDate != newDate,
              let existingWarningReason,
              Self.dateBasedWarningReasons.contains(existingWarningReason) else {
            return
        }

        let updatedWarningReason = currentDateBasedWarningReason(
            state: newState,
            txnDate: newDate
        )
        guard updatedWarningReason == nil else {
            return
        }

        try transactionRepository.clearStatusWarning(transactionID: transactionID, db: db)
    }

    private func requirePositiveAmount(
        _ amount: Double?,
        missingError: TransactionServiceError
    ) throws -> Double {
        guard let amount else {
            throw missingError
        }

        guard amount > 0 else {
            throw TransactionServiceError.invalidAmount(amount)
        }

        return amount
    }

    private func currentDateBasedWarningReason(state: String, txnDate: String) -> String? {
        let today = Self.warningDateFormatter.string(from: Date())

        if state == "cleared" && txnDate > today {
            return "cleared_future_date"
        }

        if state == "reconciling" && txnDate < today {
            return "pending_past_date"
        }

        if state == "uncleared" && txnDate < today {
            return "uncleared_past_date"
        }

        return nil
    }

    private static let dateBasedWarningReasons: Set<String> = [
        "cleared_future_date",
        "pending_past_date",
        "uncleared_past_date"
    ]

    private static let warningDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
