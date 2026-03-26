import Foundation

@MainActor
final class RecurringRuleEditorViewModel: ObservableObject {
    struct AccountOption: Identifiable, Hashable {
        let id: Int64
        let fullPath: String
        let accountClass: String
        let currency: String

        var displayName: String {
            "\(fullPath) • \(currency)"
        }
    }

    @Published var name: String
    @Published var transactionType: RecurringTransactionType
    @Published var amountText: String
    @Published var descriptionText: String
    @Published var memoText: String
    @Published var defaultState: String
    @Published var startDate: Date
    @Published var endDate: Date
    @Published var isActive: Bool
    @Published var recurrenceType: RecurrenceType
    @Published var intervalText: String
    @Published var dayOfMonthText: String
    @Published var endMode: RecurringEndMode
    @Published var maxOccurrencesText: String
    @Published var selectedSourceAccountID: Int64?
    @Published var selectedTargetAccountID: Int64?
    @Published var selectedCategoryAccountID: Int64?
    @Published private(set) var incomeCategoryOptions: [AccountOption] = []
    @Published private(set) var expenseCategoryOptions: [AccountOption] = []
    @Published private(set) var transferAccountOptions: [AccountOption] = []
    @Published private(set) var errorMessage: String?
    @Published private(set) var isSaving = false

    private let accountRepository: AccountRepository
    private let recurringService: RecurringTransactionService
    private let template: RecurringTransactionTemplate?

    init(
        accountRepository: AccountRepository,
        recurringService: RecurringTransactionService,
        template: RecurringTransactionTemplate? = nil
    ) {
        self.accountRepository = accountRepository
        self.recurringService = recurringService
        self.template = template
        self.name = template?.name ?? ""
        self.transactionType = template?.transactionType ?? .expense
        self.amountText = template.map { Self.formatAmount($0.amount) } ?? ""
        self.descriptionText = template?.description ?? ""
        self.memoText = template?.memo ?? ""
        self.defaultState = template?.defaultState ?? "uncleared"
        self.startDate = Self.dateFormatter.date(from: template?.startDate ?? "") ?? Date()
        self.endDate = Date()
        self.isActive = true
        self.recurrenceType = .monthly
        self.intervalText = "1"
        self.dayOfMonthText = template.map { String(Self.calendar.component(.day, from: Self.dateFormatter.date(from: $0.startDate) ?? Date())) } ?? ""
        self.endMode = .none
        self.maxOccurrencesText = ""
        self.selectedSourceAccountID = template?.sourceAccountID
        self.selectedTargetAccountID = template?.targetAccountID
        self.selectedCategoryAccountID = template?.categoryAccountID
    }

    func loadFormData() {
        do {
            let accounts = try accountRepository.getLeafAccounts()
            let accountsByID = Dictionary(
                uniqueKeysWithValues: accounts.compactMap { account -> (Int64, Account)? in
                    guard let accountID = account.id else { return nil }
                    return (accountID, account)
                }
            )

            let options = accounts.compactMap { account -> AccountOption? in
                guard let accountID = account.id else { return nil }
                return AccountOption(
                    id: accountID,
                    fullPath: accountPath(for: account, accountsByID: accountsByID),
                    accountClass: account.class,
                    currency: account.currency
                )
            }

            incomeCategoryOptions = options.filter { $0.accountClass == "income" }.sorted(by: sortOptions)
            expenseCategoryOptions = options.filter { $0.accountClass == "expense" }.sorted(by: sortOptions)
            transferAccountOptions = options.filter { $0.accountClass == "asset" || $0.accountClass == "liability" }.sorted(by: sortOptions)

            applyTemplateIfNeeded()
            synchronizeSelections()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func transactionTypeDidChange() {
        synchronizeSelections()
        errorMessage = nil
    }

    func save() throws {
        errorMessage = nil
        isSaving = true
        defer { isSaving = false }

        let normalizedName = normalized(name)
        let normalizedDescription = normalized(descriptionText)
        let normalizedMemo = normalized(memoText)

        guard let amount = Double(amountText.replacingOccurrences(of: ",", with: ".")), amount > 0 else {
            throw fail("Amount must be greater than zero.")
        }
        guard let intervalN = Int(intervalText), intervalN >= 1 else {
            throw fail("Interval must be at least 1.")
        }

        let dayOfMonth: Int?
        if recurrenceType == .monthlyFixedDay {
            guard let parsedDay = Int(dayOfMonthText), (1...31).contains(parsedDay) else {
                throw fail("Day of month must be between 1 and 31.")
            }
            dayOfMonth = parsedDay
        } else {
            dayOfMonth = nil
        }

        let maxOccurrences: Int?
        switch endMode {
        case .none:
            maxOccurrences = nil
        case .count:
            guard let parsedCount = Int(maxOccurrencesText), parsedCount > 0 else {
                throw fail("Maximum occurrences must be greater than zero.")
            }
            maxOccurrences = parsedCount
        case .date:
            maxOccurrences = nil
        }

        let input = RecurringRuleInput(
            name: normalizedName ?? "",
            transactionType: transactionType,
            sourceAccountID: transactionType == .expense || transactionType == .transfer ? selectedSourceAccountID : nil,
            targetAccountID: transactionType == .income || transactionType == .transfer ? selectedTargetAccountID : nil,
            categoryAccountID: transactionType == .transfer ? nil : selectedCategoryAccountID,
            amount: amount,
            currency: selectedCurrencyCode ?? "HUF",
            description: normalizedDescription,
            memo: normalizedMemo,
            defaultState: defaultState,
            recurrenceType: recurrenceType,
            intervalN: intervalN,
            dayOfMonth: dayOfMonth,
            startDate: Self.dateFormatter.string(from: startDate),
            endMode: endMode,
            maxOccurrences: maxOccurrences,
            endDate: endMode == .date ? Self.dateFormatter.string(from: endDate) : nil,
            isActive: isActive
        )

        do {
            _ = try recurringService.createRecurringRule(input: input)
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    var sourceAccountOptions: [AccountOption] { transferAccountOptions }
    var targetAccountOptions: [AccountOption] { transferAccountOptions }

    var categoryOptions: [AccountOption] {
        switch transactionType {
        case .income:
            return incomeCategoryOptions
        case .expense:
            return expenseCategoryOptions
        case .transfer:
            return []
        }
    }

    var selectedCurrencyCode: String? {
        switch transactionType {
        case .income:
            return targetAccountOptions.first(where: { $0.id == selectedTargetAccountID })?.currency
        case .expense:
            return sourceAccountOptions.first(where: { $0.id == selectedSourceAccountID })?.currency
        case .transfer:
            return sourceAccountOptions.first(where: { $0.id == selectedSourceAccountID })?.currency
        }
    }

    private func normalized(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func fail(_ message: String) -> Error {
        errorMessage = message
        return RecurringRuleEditorError.validationFailed(message)
    }

    private func synchronizeSelections() {
        switch transactionType {
        case .income:
            if !incomeCategoryOptions.contains(where: { $0.id == selectedCategoryAccountID }) {
                selectedCategoryAccountID = incomeCategoryOptions.first?.id
            }
            if !targetAccountOptions.contains(where: { $0.id == selectedTargetAccountID }) {
                selectedTargetAccountID = targetAccountOptions.first?.id
            }
            selectedSourceAccountID = nil
        case .expense:
            if !expenseCategoryOptions.contains(where: { $0.id == selectedCategoryAccountID }) {
                selectedCategoryAccountID = expenseCategoryOptions.first?.id
            }
            if !sourceAccountOptions.contains(where: { $0.id == selectedSourceAccountID }) {
                selectedSourceAccountID = sourceAccountOptions.first?.id
            }
            selectedTargetAccountID = nil
        case .transfer:
            if !sourceAccountOptions.contains(where: { $0.id == selectedSourceAccountID }) {
                selectedSourceAccountID = sourceAccountOptions.first?.id
            }
            if selectedTargetAccountID == selectedSourceAccountID ||
                !targetAccountOptions.contains(where: { $0.id == selectedTargetAccountID }) {
                selectedTargetAccountID = targetAccountOptions.first { $0.id != selectedSourceAccountID }?.id
            }
            selectedCategoryAccountID = nil
        }
    }

    private func applyTemplateIfNeeded() {
        guard let template else {
            return
        }

        transactionType = template.transactionType
        name = template.name
        amountText = Self.formatAmount(template.amount)
        descriptionText = template.description ?? ""
        memoText = template.memo ?? ""
        defaultState = template.defaultState
        if let parsedStartDate = Self.dateFormatter.date(from: template.startDate) {
            startDate = parsedStartDate
            if recurrenceType == .monthlyFixedDay {
                dayOfMonthText = String(Self.calendar.component(.day, from: parsedStartDate))
            }
        }
        selectedSourceAccountID = optionIDIfAvailable(template.sourceAccountID, in: sourceAccountOptions)
        selectedTargetAccountID = optionIDIfAvailable(template.targetAccountID, in: targetAccountOptions)
        selectedCategoryAccountID = optionIDIfAvailable(template.categoryAccountID, in: categoryOptionsForType(template.transactionType))
    }

    private func categoryOptionsForType(_ type: RecurringTransactionType) -> [AccountOption] {
        switch type {
        case .income:
            return incomeCategoryOptions
        case .expense:
            return expenseCategoryOptions
        case .transfer:
            return []
        }
    }

    private func optionIDIfAvailable(_ accountID: Int64?, in options: [AccountOption]) -> Int64? {
        guard let accountID else {
            return nil
        }
        return options.contains(where: { $0.id == accountID }) ? accountID : nil
    }

    private func accountPath(for account: Account, accountsByID: [Int64: Account]) -> String {
        var components = [account.name]
        var currentParentID = account.parentID

        while let parentID = currentParentID,
              let parent = accountsByID[parentID] {
            components.append(parent.name)
            currentParentID = parent.parentID
        }

        return components.reversed().joined(separator: " / ")
    }

    private func sortOptions(_ lhs: AccountOption, _ rhs: AccountOption) -> Bool {
        lhs.fullPath.localizedCaseInsensitiveCompare(rhs.fullPath) == .orderedAscending
    }

    private static let calendar = Calendar(identifier: .gregorian)

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static func formatAmount(_ amount: Double) -> String {
        String(format: "%.2f", amount)
    }
}

enum RecurringRuleEditorError: Error, LocalizedError {
    case validationFailed(String)

    var errorDescription: String? {
        switch self {
        case .validationFailed(let message):
            return message
        }
    }
}
