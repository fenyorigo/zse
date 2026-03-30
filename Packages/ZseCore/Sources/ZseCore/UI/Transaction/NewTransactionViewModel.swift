import Foundation

enum NewTransactionType: String, CaseIterable, Identifiable {
    case deposit
    case spending
    case transfer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .deposit:
            return "Deposit"
        case .spending:
            return "Spending"
        case .transfer:
            return "Transfer to Another Account"
        }
    }
}

@MainActor
final class NewTransactionViewModel: ObservableObject {
    struct AccountOption: Identifiable, Hashable {
        let id: Int64
        let name: String
        let accountClass: String
        let currency: String
        let fullPath: String

        var displayName: String {
            "\(fullPath) • \(currency)"
        }
    }

    @Published var transactionType: NewTransactionType = .deposit
    @Published var date = Date()
    @Published var descriptionText = ""
    @Published var state = "uncleared"
    @Published var selectedCategoryAccountID: Int64?
    @Published var selectedFromAccountID: Int64?
    @Published var selectedToAccountID: Int64?
    @Published var partnerName = ""
    @Published var amountText = ""
    @Published var sourceAmountText = ""
    @Published var targetAmountText = ""
    @Published var memo = ""
    @Published private(set) var incomeCategoryOptions: [AccountOption] = []
    @Published private(set) var expenseCategoryOptions: [AccountOption] = []
    @Published private(set) var transferAccountOptions: [AccountOption] = []
    @Published private(set) var isSaving = false
    @Published private(set) var errorMessage: String?

    let currentAccount: Account

    private let accountRepository: AccountRepository
    private let transactionService: TransactionService

    init(
        currentAccount: Account,
        accountRepository: AccountRepository,
        transactionService: TransactionService
    ) {
        self.currentAccount = currentAccount
        self.accountRepository = accountRepository
        self.transactionService = transactionService
        self.selectedFromAccountID = currentAccount.id
    }

    func loadFormData() {
        do {
            let allAccounts = try accountRepository.getAllAccounts()
            let accounts = try accountRepository.getLeafAccounts()
            let accountsByID: [Int64: Account] = Dictionary(
                uniqueKeysWithValues: allAccounts.compactMap { account in
                    guard let accountID = account.id else {
                        return nil
                    }
                    return (accountID, account)
                }
            )

            let options = accounts.compactMap { account -> AccountOption? in
                guard let accountID = account.id else {
                    return nil
                }

                return AccountOption(
                    id: accountID,
                    name: account.name,
                    accountClass: account.class,
                    currency: account.currency,
                    fullPath: accountPath(for: account, accountsByID: accountsByID)
                )
            }

            incomeCategoryOptions = options
                .filter { $0.accountClass == "income" && $0.currency == currentAccount.currency }
                .sorted(by: optionSort)

            expenseCategoryOptions = options
                .filter { $0.accountClass == "expense" && $0.currency == currentAccount.currency }
                .sorted(by: optionSort)

            transferAccountOptions = options
                .filter { option in
                    return option.accountClass == "asset" || option.accountClass == "liability"
                }
                .sorted(by: optionSort)

            synchronizeSelectionsForCurrentType()
            errorMessage = nil
        } catch {
            incomeCategoryOptions = []
            expenseCategoryOptions = []
            transferAccountOptions = []
            errorMessage = error.localizedDescription
        }
    }

    func transactionTypeDidChange() {
        synchronizeSelectionsForCurrentType()
        errorMessage = nil
    }

    func save() throws -> Int64 {
        errorMessage = nil

        let formattedDate = Self.dateFormatter.string(from: date)
        let normalizedDescription = normalized(descriptionText)
        let normalizedPartner = normalized(partnerName)
        let normalizedMemo = normalized(memo)

        isSaving = true
        defer { isSaving = false }

        do {
            let transaction: Transaction

            switch transactionType {
            case .deposit:
                guard let currentAccountID = currentAccount.id else {
                    return try fail("The current account is missing an identifier.")
                }
                guard let incomeCategoryID = selectedCategoryAccountID else {
                    return try fail("Choose an income category.")
                }

                transaction = try transactionService.createDeposit(
                    currentAccountID: currentAccountID,
                    incomeCategoryAccountID: incomeCategoryID,
                    date: formattedDate,
                    description: normalizedDescription,
                    state: state,
                    amount: try parsedPrimaryAmount(),
                    partnerName: normalizedPartner,
                    memo: normalizedMemo
                )
            case .spending:
                guard let currentAccountID = currentAccount.id else {
                    return try fail("The current account is missing an identifier.")
                }
                guard let expenseCategoryID = selectedCategoryAccountID else {
                    return try fail("Choose an expense category.")
                }

                transaction = try transactionService.createSpending(
                    currentAccountID: currentAccountID,
                    expenseCategoryAccountID: expenseCategoryID,
                    date: formattedDate,
                    description: normalizedDescription,
                    state: state,
                    amount: try parsedPrimaryAmount(),
                    partnerName: normalizedPartner,
                    memo: normalizedMemo
                )
            case .transfer:
                guard let fromAccountID = selectedFromAccountID else {
                    return try fail("Choose a from account.")
                }
                guard let toAccountID = selectedToAccountID else {
                    return try fail("Choose a to account.")
                }

                transaction = try transactionService.createTransfer(
                    sourceAccountID: fromAccountID,
                    targetAccountID: toAccountID,
                    sourceAmount: try parsedTransferSourceAmount(),
                    targetAmount: try parsedTransferTargetAmount(),
                    date: formattedDate,
                    description: normalizedDescription,
                    state: state,
                    partnerName: normalizedPartner,
                    memo: normalizedMemo
                )
            }

            return transaction.id ?? 0
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    var currentAccountDisplayName: String {
        "\(currentAccount.name) (\(currentAccount.currency))"
    }

    var fromAccountOptions: [AccountOption] {
        transferAccountOptions
    }

    var toAccountOptions: [AccountOption] {
        transferAccountOptions.filter { $0.id != selectedFromAccountID }
    }

    var selectedCategoryOptions: [AccountOption] {
        switch transactionType {
        case .deposit:
            return incomeCategoryOptions
        case .spending:
            return expenseCategoryOptions
        case .transfer:
            return []
        }
    }

    var categoryLabel: String {
        switch transactionType {
        case .deposit:
            return "Income Category"
        case .spending:
            return "Expense Category"
        case .transfer:
            return "Category"
        }
    }

    var canSave: Bool {
        !isSaving
    }

    var isCrossCurrencyTransfer: Bool {
        guard transactionType == .transfer,
              let fromAccount = selectedFromAccount,
              let toAccount = selectedToAccount else {
            return false
        }
        return fromAccount.currency != toAccount.currency
    }

    var transferSourceCurrency: String {
        selectedFromAccount?.currency ?? currentAccount.currency
    }

    var transferTargetCurrency: String {
        selectedToAccount?.currency ?? currentAccount.currency
    }

    var effectiveRateText: String? {
        guard isCrossCurrencyTransfer,
              let sourceAmount = amountValue(from: sourceAmountText),
              let targetAmount = amountValue(from: targetAmountText),
              sourceAmount > 0,
              targetAmount > 0 else {
            return nil
        }

        return String(
            format: "Effective rate: %.4f %@/%@",
            sourceAmount / targetAmount,
            transferSourceCurrency,
            transferTargetCurrency
        )
    }

    private func normalized(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func fail(_ message: String) throws -> Int64 {
        errorMessage = message
        throw NewTransactionError.validationFailed(message)
    }

    private func failValidation(_ message: String) throws -> Never {
        errorMessage = message
        throw NewTransactionError.validationFailed(message)
    }

    private func synchronizeSelectionsForCurrentType() {
        if selectedFromAccountID == nil {
            selectedFromAccountID = currentAccount.id
        }

        switch transactionType {
        case .deposit:
            if !incomeCategoryOptions.contains(where: { $0.id == selectedCategoryAccountID }) {
                selectedCategoryAccountID = incomeCategoryOptions.first?.id
            }
        case .spending:
            if !expenseCategoryOptions.contains(where: { $0.id == selectedCategoryAccountID }) {
                selectedCategoryAccountID = expenseCategoryOptions.first?.id
            }
        case .transfer:
            if selectedFromAccountID == selectedToAccountID {
                selectedToAccountID = nil
            }

            if selectedToAccountID == nil || !toAccountOptions.contains(where: { $0.id == selectedToAccountID }) {
                selectedToAccountID = toAccountOptions.first?.id
            }

            if !isCrossCurrencyTransfer,
               let sourceAmount = amountValue(from: sourceAmountText),
               sourceAmount > 0,
               amountText.isEmpty {
                amountText = Self.formattedAmount(sourceAmount)
            }
        }
    }

    private func optionSort(_ lhs: AccountOption, _ rhs: AccountOption) -> Bool {
        lhs.fullPath.localizedCaseInsensitiveCompare(rhs.fullPath) == .orderedAscending
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

    private var selectedFromAccount: AccountOption? {
        fromAccountOptions.first { $0.id == selectedFromAccountID }
    }

    private var selectedToAccount: AccountOption? {
        toAccountOptions.first { $0.id == selectedToAccountID }
            ?? transferAccountOptions.first { $0.id == selectedToAccountID }
    }

    private func parsedPrimaryAmount() throws -> Double {
        guard let amount = amountValue(from: amountText) else {
            try failValidation("Enter a valid amount.")
        }

        guard amount > 0 else {
            try failValidation("Amount must be greater than zero.")
        }

        return amount
    }

    private func parsedTransferSourceAmount() throws -> Double {
        if isCrossCurrencyTransfer {
            guard let amount = amountValue(from: sourceAmountText) else {
                try failValidation("Enter a valid source amount.")
            }

            guard amount > 0 else {
                try failValidation("Source amount must be greater than zero.")
            }

            return amount
        }

        return try parsedPrimaryAmount()
    }

    private func parsedTransferTargetAmount() throws -> Double? {
        guard isCrossCurrencyTransfer else {
            return nil
        }

        guard let amount = amountValue(from: targetAmountText) else {
            try failValidation("Enter a valid target amount.")
        }

        guard amount > 0 else {
            try failValidation("Target amount must be greater than zero.")
        }

        return amount
    }

    private func amountValue(from text: String) -> Double? {
        Double(text.replacingOccurrences(of: ",", with: "."))
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static func formattedAmount(_ amount: Double) -> String {
        String(format: "%.2f", amount)
    }
}

enum NewTransactionError: Error, LocalizedError {
    case validationFailed(String)

    var errorDescription: String? {
        switch self {
        case .validationFailed(let message):
            return message
        }
    }
}
