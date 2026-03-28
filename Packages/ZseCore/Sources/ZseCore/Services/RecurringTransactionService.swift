import Foundation
import GRDB

struct RecurringRuleInput {
    let name: String
    let transactionType: RecurringTransactionType
    let sourceAccountID: Int64?
    let targetAccountID: Int64?
    let categoryAccountID: Int64?
    let amount: Double
    let currency: String
    let description: String?
    let memo: String?
    let defaultState: String
    let recurrenceType: RecurrenceType
    let intervalN: Int
    let dayOfMonth: Int?
    let startDate: String
    let endMode: RecurringEndMode
    let maxOccurrences: Int?
    let endDate: String?
    let isActive: Bool
}

struct RecurringTransactionTemplate {
    let name: String
    let transactionType: RecurringTransactionType
    let sourceAccountID: Int64?
    let targetAccountID: Int64?
    let categoryAccountID: Int64?
    let amount: Double
    let currency: String
    let description: String?
    let memo: String?
    let defaultState: String
    let startDate: String
}

struct RecurringTransactionService {
    private let accountRepository: AccountRepository
    private let recurringRuleRepository: RecurringRuleRepository
    private let transactionRepository: TransactionRepository
    private let transactionService: TransactionService
    private let allowedStates: Set<String> = ["uncleared", "reconciling", "cleared"]

    init(
        accountRepository: AccountRepository,
        recurringRuleRepository: RecurringRuleRepository,
        transactionRepository: TransactionRepository,
        transactionService: TransactionService
    ) {
        self.accountRepository = accountRepository
        self.recurringRuleRepository = recurringRuleRepository
        self.transactionRepository = transactionRepository
        self.transactionService = transactionService
    }

    @discardableResult
    func createRecurringRule(input: RecurringRuleInput) throws -> RecurringRule {
        try recurringRuleRepository.writeInTransaction { db in
            let validatedRule = try validateRuleInput(input, db: db)
            var rule = RecurringRule(
                name: validatedRule.name,
                transactionType: validatedRule.transactionType,
                sourceAccountID: validatedRule.sourceAccountID,
                targetAccountID: validatedRule.targetAccountID,
                categoryAccountID: validatedRule.categoryAccountID,
                amount: validatedRule.amount,
                currency: validatedRule.currency,
                description: validatedRule.description,
                memo: validatedRule.memo,
                defaultState: validatedRule.defaultState,
                recurrenceType: validatedRule.recurrenceType,
                intervalN: validatedRule.intervalN,
                dayOfMonth: validatedRule.dayOfMonth,
                startDate: validatedRule.startDate,
                endMode: validatedRule.endMode,
                maxOccurrences: validatedRule.maxOccurrences,
                endDate: validatedRule.endDate,
                nextDueDate: validatedRule.isActive ? validatedRule.startDate : nil,
                isActive: validatedRule.isActive
            )
            try recurringRuleRepository.createRule(&rule, db: db)
            return rule
        }
    }

    func generateDueRecurringTransactions(today: Date = Date()) throws -> Int {
        try generateRecurringTransactions(through: today)
    }

    func generateRecurringTransactions(through horizonDate: Date) throws -> Int {
        let horizonDateString = Self.dateFormatter.string(from: horizonDate)

        return try recurringRuleRepository.writeInTransaction { db in
            let candidateRules = try recurringRuleRepository.fetchRules(nextDueOnOrBefore: horizonDateString, db: db)
            var generatedCount = 0

            for var rule in candidateRules {
                while let nextDueDate = rule.nextDueDate, nextDueDate <= horizonDateString {
                    if try shouldStopGeneration(for: rule, nextDueDate: nextDueDate, db: db) {
                        rule.nextDueDate = nil
                        rule.updatedAt = Self.timestamp()
                        try recurringRuleRepository.updateRule(rule, db: db)
                        break
                    }

                    if let ruleID = rule.id,
                       try !recurringRuleRepository.hasGeneratedOccurrence(
                        ruleID: ruleID,
                        occurrenceDate: nextDueDate,
                        db: db
                       ) {
                        var transaction = try makeGeneratedTransaction(from: rule, occurrenceDate: nextDueDate)
                        var entries = try makeGeneratedEntries(from: rule, db: db)
                        try transactionRepository.createTransaction(&transaction, entries: &entries, db: db)
                        generatedCount += 1
                    }

                    rule.nextDueDate = try nextOccurrenceDate(after: nextDueDate, for: rule)
                    if let nextDueDate = rule.nextDueDate,
                       try shouldStopGeneration(for: rule, nextDueDate: nextDueDate, db: db) {
                        rule.nextDueDate = nil
                    }
                    rule.updatedAt = Self.timestamp()
                    try recurringRuleRepository.updateRule(rule, db: db)
                }
            }

            return generatedCount
        }
    }

    func makeTemplateFromTransaction(transactionID: Int64, currentAccountID: Int64) throws -> RecurringTransactionTemplate {
        try transactionRepository.writeInTransaction { db in
            let entries = try transactionRepository.fetchEntries(for: transactionID, db: db)
            guard entries.count == 2 else {
                throw RecurringRuleError.unsupportedTemplateTransaction
            }

            guard let currentAccount = try accountRepository.getAccount(id: currentAccountID, db: db) else {
                throw TransactionServiceError.accountNotFound(currentAccountID)
            }

            guard currentAccount.class == "asset" || currentAccount.class == "liability" else {
                throw RecurringRuleError.unsupportedTemplateTransaction
            }

            guard let currentEntry = entries.first(where: { $0.accountID == currentAccountID }),
                  let counterpartEntry = entries.first(where: { $0.accountID != currentAccountID }),
                  let counterpartAccount = try accountRepository.getAccount(id: counterpartEntry.accountID, db: db),
                  let transaction = try Transaction.fetchOne(db, key: transactionID) else {
                throw RecurringRuleError.unsupportedTemplateTransaction
            }

            if currentEntry.currency != counterpartEntry.currency {
                throw RecurringRuleError.crossCurrencyRecurringNotSupported
            }

            let memo = [currentEntry.memo, counterpartEntry.memo].compactMap { $0 }.first

            if counterpartAccount.class == "income" {
                return RecurringTransactionTemplate(
                    name: transaction.description ?? "Recurring Income",
                    transactionType: .income,
                    sourceAccountID: nil,
                    targetAccountID: currentAccountID,
                    categoryAccountID: counterpartAccount.id,
                    amount: abs(currentEntry.amount),
                    currency: currentEntry.currency,
                    description: transaction.description,
                    memo: memo,
                    defaultState: transaction.state,
                    startDate: transaction.txnDate
                )
            }

            if counterpartAccount.class == "expense" {
                return RecurringTransactionTemplate(
                    name: transaction.description ?? "Recurring Expense",
                    transactionType: .expense,
                    sourceAccountID: currentAccountID,
                    targetAccountID: nil,
                    categoryAccountID: counterpartAccount.id,
                    amount: abs(currentEntry.amount),
                    currency: currentEntry.currency,
                    description: transaction.description,
                    memo: memo,
                    defaultState: transaction.state,
                    startDate: transaction.txnDate
                )
            }

            if counterpartAccount.class == "asset" || counterpartAccount.class == "liability" {
                let sourceAccountID: Int64
                let targetAccountID: Int64
                if currentEntry.amount < 0 {
                    sourceAccountID = currentAccountID
                    targetAccountID = counterpartAccount.id ?? 0
                } else {
                    sourceAccountID = counterpartAccount.id ?? 0
                    targetAccountID = currentAccountID
                }

                return RecurringTransactionTemplate(
                    name: transaction.description ?? "Recurring Transfer",
                    transactionType: .transfer,
                    sourceAccountID: sourceAccountID,
                    targetAccountID: targetAccountID,
                    categoryAccountID: nil,
                    amount: abs(currentEntry.amount),
                    currency: currentEntry.currency,
                    description: transaction.description,
                    memo: memo,
                    defaultState: transaction.state,
                    startDate: transaction.txnDate
                )
            }

            throw RecurringRuleError.unsupportedTemplateTransaction
        }
    }

    private func validateRuleInput(_ input: RecurringRuleInput, db: Database) throws -> RecurringRuleInput {
        let trimmedName = input.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = trimmedName.isEmpty ? defaultName(for: input.transactionType) : trimmedName

        guard input.amount > 0 else {
            throw RecurringRuleError.invalidAmount
        }
        guard input.intervalN >= 1 else {
            throw RecurringRuleError.invalidInterval
        }
        guard allowedStates.contains(input.defaultState) else {
            throw TransactionServiceError.invalidState(input.defaultState)
        }
        guard Self.dateFormatter.date(from: input.startDate) != nil else {
            throw RecurringRuleError.invalidStartDate
        }
        if let endDate = input.endDate {
            guard Self.dateFormatter.date(from: endDate) != nil else {
                throw RecurringRuleError.invalidEndDate
            }
        }

        let normalizedEndMode: RecurringEndMode
        let normalizedMaxOccurrences: Int?
        let normalizedEndDate: String?
        switch input.endMode {
        case .none:
            normalizedEndMode = .none
            normalizedMaxOccurrences = nil
            normalizedEndDate = nil
        case .count:
            guard let maxOccurrences = input.maxOccurrences, maxOccurrences > 0 else {
                throw RecurringRuleError.invalidMaxOccurrences
            }
            normalizedEndMode = .count
            normalizedMaxOccurrences = maxOccurrences
            normalizedEndDate = nil
        case .date:
            guard let endDate = input.endDate else {
                throw RecurringRuleError.invalidEndDate
            }
            guard endDate >= input.startDate else {
                throw RecurringRuleError.endDateBeforeStartDate
            }
            normalizedEndMode = .date
            normalizedMaxOccurrences = nil
            normalizedEndDate = endDate
        }

        switch input.recurrenceType {
        case .monthlyFixedDay:
            guard let dayOfMonth = input.dayOfMonth, (1...31).contains(dayOfMonth) else {
                throw RecurringRuleError.invalidDayOfMonth
            }
        case .daily, .weekly, .monthly:
            break
        }

        switch input.transactionType {
        case .income:
            guard let targetAccountID = input.targetAccountID,
                  let categoryAccountID = input.categoryAccountID else {
                throw RecurringRuleError.missingRequiredAccounts
            }
            let targetAccount = try requirePostableLeafAccount(id: targetAccountID, db: db)
            let categoryAccount = try requirePostableLeafAccount(id: categoryAccountID, db: db)
            guard categoryAccount.class == "income" else {
                throw RecurringRuleError.invalidCategoryClass(expected: "income")
            }
            guard targetAccount.currency == categoryAccount.currency else {
                throw RecurringRuleError.currencyMismatch
            }
            return RecurringRuleInput(
                name: resolvedName,
                transactionType: input.transactionType,
                sourceAccountID: nil,
                targetAccountID: targetAccountID,
                categoryAccountID: categoryAccountID,
                amount: input.amount,
                currency: targetAccount.currency,
                description: input.description,
                memo: input.memo,
                defaultState: input.defaultState,
                recurrenceType: input.recurrenceType,
                intervalN: input.intervalN,
                dayOfMonth: input.dayOfMonth,
                startDate: input.startDate,
                endMode: normalizedEndMode,
                maxOccurrences: normalizedMaxOccurrences,
                endDate: normalizedEndDate,
                isActive: input.isActive
            )
        case .expense:
            guard let sourceAccountID = input.sourceAccountID,
                  let categoryAccountID = input.categoryAccountID else {
                throw RecurringRuleError.missingRequiredAccounts
            }
            let sourceAccount = try requirePostableLeafAccount(id: sourceAccountID, db: db)
            let categoryAccount = try requirePostableLeafAccount(id: categoryAccountID, db: db)
            guard categoryAccount.class == "expense" else {
                throw RecurringRuleError.invalidCategoryClass(expected: "expense")
            }
            guard sourceAccount.currency == categoryAccount.currency else {
                throw RecurringRuleError.currencyMismatch
            }
            return RecurringRuleInput(
                name: resolvedName,
                transactionType: input.transactionType,
                sourceAccountID: sourceAccountID,
                targetAccountID: nil,
                categoryAccountID: categoryAccountID,
                amount: input.amount,
                currency: sourceAccount.currency,
                description: input.description,
                memo: input.memo,
                defaultState: input.defaultState,
                recurrenceType: input.recurrenceType,
                intervalN: input.intervalN,
                dayOfMonth: input.dayOfMonth,
                startDate: input.startDate,
                endMode: normalizedEndMode,
                maxOccurrences: normalizedMaxOccurrences,
                endDate: normalizedEndDate,
                isActive: input.isActive
            )
        case .transfer:
            guard let sourceAccountID = input.sourceAccountID,
                  let targetAccountID = input.targetAccountID else {
                throw RecurringRuleError.missingRequiredAccounts
            }
            guard sourceAccountID != targetAccountID else {
                throw TransactionServiceError.duplicateAccounts
            }
            let sourceAccount = try requirePostableLeafAccount(id: sourceAccountID, db: db)
            let targetAccount = try requirePostableLeafAccount(id: targetAccountID, db: db)
            guard sourceAccount.currency == targetAccount.currency else {
                throw RecurringRuleError.crossCurrencyRecurringNotSupported
            }
            return RecurringRuleInput(
                name: resolvedName,
                transactionType: input.transactionType,
                sourceAccountID: sourceAccountID,
                targetAccountID: targetAccountID,
                categoryAccountID: nil,
                amount: input.amount,
                currency: sourceAccount.currency,
                description: input.description,
                memo: input.memo,
                defaultState: input.defaultState,
                recurrenceType: input.recurrenceType,
                intervalN: input.intervalN,
                dayOfMonth: input.dayOfMonth,
                startDate: input.startDate,
                endMode: normalizedEndMode,
                maxOccurrences: normalizedMaxOccurrences,
                endDate: normalizedEndDate,
                isActive: input.isActive
            )
        }
    }

    private func shouldStopGeneration(for rule: RecurringRule, nextDueDate: String, db: Database) throws -> Bool {
        switch rule.endMode {
        case .none:
            return false
        case .date:
            guard let endDate = rule.endDate else {
                return false
            }
            return nextDueDate > endDate
        case .count:
            guard let ruleID = rule.id, let maxOccurrences = rule.maxOccurrences else {
                return false
            }
            let generatedCount = try recurringRuleRepository.generatedOccurrenceCount(ruleID: ruleID, db: db)
            return generatedCount >= maxOccurrences
        }
    }

    private func makeGeneratedTransaction(from rule: RecurringRule, occurrenceDate: String) throws -> Transaction {
        Transaction(
            txnDate: occurrenceDate,
            description: rule.description,
            state: rule.defaultState,
            recurringRuleID: rule.id,
            recurringOccurrenceDate: occurrenceDate
        )
    }

    private func makeGeneratedEntries(from rule: RecurringRule, db: Database) throws -> [Entry] {
        switch rule.transactionType {
        case .income:
            guard let targetAccountID = rule.targetAccountID,
                  let categoryAccountID = rule.categoryAccountID else {
                throw RecurringRuleError.missingRequiredAccounts
            }
            _ = try requirePostableLeafAccount(id: targetAccountID, db: db)
            _ = try requirePostableLeafAccount(id: categoryAccountID, db: db)
            return [
                Entry(accountID: targetAccountID, amount: rule.amount, currency: rule.currency, memo: rule.memo),
                Entry(accountID: categoryAccountID, amount: -rule.amount, currency: rule.currency, memo: rule.memo)
            ]
        case .expense:
            guard let sourceAccountID = rule.sourceAccountID,
                  let categoryAccountID = rule.categoryAccountID else {
                throw RecurringRuleError.missingRequiredAccounts
            }
            _ = try requirePostableLeafAccount(id: sourceAccountID, db: db)
            _ = try requirePostableLeafAccount(id: categoryAccountID, db: db)
            return [
                Entry(accountID: categoryAccountID, amount: rule.amount, currency: rule.currency, memo: rule.memo),
                Entry(accountID: sourceAccountID, amount: -rule.amount, currency: rule.currency, memo: rule.memo)
            ]
        case .transfer:
            guard let sourceAccountID = rule.sourceAccountID,
                  let targetAccountID = rule.targetAccountID else {
                throw RecurringRuleError.missingRequiredAccounts
            }
            _ = try requirePostableLeafAccount(id: sourceAccountID, db: db)
            _ = try requirePostableLeafAccount(id: targetAccountID, db: db)
            return [
                Entry(accountID: targetAccountID, amount: rule.amount, currency: rule.currency, memo: rule.memo),
                Entry(accountID: sourceAccountID, amount: -rule.amount, currency: rule.currency, memo: rule.memo)
            ]
        }
    }

    private func nextOccurrenceDate(after dateString: String, for rule: RecurringRule) throws -> String? {
        guard let date = Self.dateFormatter.date(from: dateString) else {
            throw RecurringRuleError.invalidStartDate
        }

        let nextDate: Date?
        switch rule.recurrenceType {
        case .daily:
            nextDate = Self.calendar.date(byAdding: .day, value: rule.intervalN, to: date)
        case .weekly:
            nextDate = Self.calendar.date(byAdding: .weekOfYear, value: rule.intervalN, to: date)
        case .monthly:
            nextDate = Self.calendar.date(byAdding: .month, value: rule.intervalN, to: date)
        case .monthlyFixedDay:
            let nextBaseDate = Self.calendar.date(byAdding: .month, value: rule.intervalN, to: date)
            guard let nextBaseDate else {
                return nil
            }
            let day = rule.dayOfMonth ?? Self.calendar.component(.day, from: nextBaseDate)
            var components = Self.calendar.dateComponents([.year, .month], from: nextBaseDate)
            let range = Self.calendar.range(of: .day, in: .month, for: nextBaseDate)
            components.day = min(day, range?.count ?? day)
            nextDate = Self.calendar.date(from: components)
        }

        guard let nextDate else {
            return nil
        }
        return Self.dateFormatter.string(from: nextDate)
    }

    private func requirePostableLeafAccount(id: Int64, db: Database) throws -> Account {
        guard let account = try accountRepository.getAccount(id: id, db: db) else {
            throw TransactionServiceError.accountNotFound(id)
        }
        guard !account.isGroup else {
            throw TransactionServiceError.groupAccountNotPostable(id)
        }
        guard !(try accountRepository.hasChildren(accountID: id, db: db)) else {
            throw TransactionServiceError.nonLeafAccountNotPostable(id)
        }
        return account
    }

    private func defaultName(for type: RecurringTransactionType) -> String {
        switch type {
        case .income:
            return "Recurring Income"
        case .expense:
            return "Recurring Expense"
        case .transfer:
            return "Recurring Transfer"
        }
    }

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static func timestamp() -> String {
        Account.makeTimestamp()
    }

    func recurringPreviewHorizonDate(from referenceDate: Date = Date()) -> Date {
        Self.calendar.date(byAdding: .year, value: 1, to: referenceDate) ?? referenceDate
    }
}

enum RecurringRuleError: Error, LocalizedError {
    case invalidAmount
    case invalidInterval
    case invalidStartDate
    case invalidEndDate
    case endDateBeforeStartDate
    case invalidMaxOccurrences
    case invalidDayOfMonth
    case missingRequiredAccounts
    case invalidCategoryClass(expected: String)
    case currencyMismatch
    case unsupportedTemplateTransaction
    case crossCurrencyRecurringNotSupported

    var errorDescription: String? {
        switch self {
        case .invalidAmount:
            return "Recurring amount must be greater than zero."
        case .invalidInterval:
            return "Interval must be at least 1."
        case .invalidStartDate:
            return "Enter a valid start date."
        case .invalidEndDate:
            return "Enter a valid end date."
        case .endDateBeforeStartDate:
            return "End date must be on or after the start date."
        case .invalidMaxOccurrences:
            return "Maximum occurrences must be greater than zero."
        case .invalidDayOfMonth:
            return "Day of month must be between 1 and 31."
        case .missingRequiredAccounts:
            return "Select the required accounts for this recurring rule."
        case .invalidCategoryClass(let expected):
            return "The selected category must be an \(expected) account."
        case .currencyMismatch:
            return "Recurring income and expense rules require matching currencies."
        case .unsupportedTemplateTransaction:
            return "Recurring v1 can only be created from simple income, expense, or same-currency transfer transactions."
        case .crossCurrencyRecurringNotSupported:
            return "Cross-currency recurring transfers are not supported yet."
        }
    }
}
