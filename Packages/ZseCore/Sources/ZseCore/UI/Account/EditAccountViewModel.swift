import Foundation

@MainActor
final class EditAccountViewModel: ObservableObject {
    struct ParentAccountOption: Identifiable {
        let id: Int64
        let name: String
        let currency: String
        let subtitle: String
    }

    let accountClasses = ["asset", "liability", "income", "expense"]
    let accountSubtypes = [
        "bank",
        "cash",
        "credit",
        "investment",
        "pension",
        "loan",
        "receivable",
        "custodial",
        "group"
    ]

    @Published var name: String
    @Published var selectedParentAccountID: Int64?
    @Published var accountClass: String
    @Published var subtype: String
    @Published var currencyCode: String
    @Published var isGroup: Bool
    @Published var isHidden: Bool
    @Published var includeInNetWorth: Bool
    @Published var accumulationCurrencyCode: String?
    @Published var creditLimitText: String
    @Published var creditAvailabilityWarningPercentText: String
    @Published var openingBalanceText: String
    @Published var hasOpeningBalanceDate: Bool
    @Published var openingBalanceDate: Date
    @Published var sortOrderText: String
    @Published private(set) var availableParents: [ParentAccountOption] = []
    @Published private(set) var availableCurrencies: [Currency] = []
    @Published private(set) var errorMessage: String?
    @Published private(set) var isSaving = false

    private let originalAccount: Account
    private let accountRepository: AccountRepository
    private let currencyRepository: CurrencyRepository
    private var previousParentAccountID: Int64?
    private(set) var canEditAccumulationCurrency = false

    init(
        account: Account,
        accountRepository: AccountRepository,
        currencyRepository: CurrencyRepository
    ) {
        self.originalAccount = account
        self.accountRepository = accountRepository
        self.currencyRepository = currencyRepository
        self.name = account.name
        self.selectedParentAccountID = account.parentID
        self.accountClass = account.class
        self.subtype = account.subtype
        self.currencyCode = account.currency
        self.isGroup = account.isGroup
        self.isHidden = account.isHidden
        self.includeInNetWorth = account.includeInNetWorth
        self.accumulationCurrencyCode = account.accumulationCurrency
        self.creditLimitText = account.creditLimit.map { String($0) } ?? ""
        self.creditAvailabilityWarningPercentText = account.creditAvailabilityWarningPercent.map { String($0) } ?? ""
        self.openingBalanceText = account.openingBalance.map { String($0) } ?? ""
        self.hasOpeningBalanceDate = account.openingBalanceDate != nil
        self.openingBalanceDate = Self.dateFormatter.date(from: account.openingBalanceDate ?? "") ?? Date()
        self.sortOrderText = "\(account.sortOrder)"
        self.previousParentAccountID = account.parentID
    }

    func loadFormData() {
        do {
            let parentAccounts = try accountRepository.getAllAccounts()
            let accountsByID: [Int64: Account] = Dictionary(
                uniqueKeysWithValues: parentAccounts.compactMap { account in
                    guard let accountID = account.id else {
                        return nil
                    }
                    return (accountID, account)
                }
            )

            availableParents = parentAccounts.compactMap { account in
                guard let accountID = account.id, accountID != originalAccount.id else {
                    return nil
                }

                return ParentAccountOption(
                    id: accountID,
                    name: accountPath(for: account, accountsByID: accountsByID),
                    currency: account.currency,
                    subtitle: "\(account.subtype) • \(account.currency)"
                )
            }

            availableCurrencies = try currencyRepository.getAllCurrencies()
            canEditAccumulationCurrency = isEligibleForAccumulationCurrency()
            errorMessage = nil
        } catch {
            availableParents = []
            availableCurrencies = []
            canEditAccumulationCurrency = false
            errorMessage = error.localizedDescription
        }
    }

    func save() throws -> Int64 {
        errorMessage = nil

        guard let accountID = originalAccount.id else {
            return try fail("The selected account is missing an identifier.")
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            return try fail("Name is required.")
        }

        guard accountClasses.contains(accountClass) else {
            return try fail("Choose a valid class.")
        }

        guard accountSubtypes.contains(subtype) else {
            return try fail("Choose a valid subtype.")
        }

        guard !currencyCode.isEmpty else {
            return try fail("Choose a currency.")
        }

        let openingBalance = try parseOpeningBalance()
        let creditLimit = try parseCreditLimit()
        let creditAvailabilityWarningPercent = try parseCreditAvailabilityWarningPercent()
        let openingBalanceDateString = hasOpeningBalanceDate
            ? Self.dateFormatter.string(from: openingBalanceDate)
            : nil

        if selectedParentAccountID == accountID {
            return try fail("An account cannot be its own parent.")
        }

        if let parentAccountID = selectedParentAccountID {
            guard try accountRepository.getAccount(id: parentAccountID) != nil else {
                return try fail("Selected parent account does not exist.")
            }
        }

        guard !currencyCode.isEmpty else {
            return try fail("Choose a currency.")
        }

        isSaving = true
        defer { isSaving = false }

        var updatedAccount = originalAccount
        updatedAccount.parentID = selectedParentAccountID
        updatedAccount.name = trimmedName
        updatedAccount.class = accountClass
        updatedAccount.subtype = subtype
        updatedAccount.currency = currencyCode
        updatedAccount.isGroup = isGroup
        updatedAccount.isHidden = isHidden
        updatedAccount.includeInNetWorth = includeInNetWorth
        updatedAccount.accumulationCurrency = canEditAccumulationCurrency ? accumulationCurrencyCode : nil
        updatedAccount.creditLimit = isCreditLimitEditable ? creditLimit : nil
        updatedAccount.creditAvailabilityWarningPercent = isCreditLimitEditable ? creditAvailabilityWarningPercent : nil
        updatedAccount.openingBalance = openingBalance
        updatedAccount.openingBalanceDate = openingBalanceDateString
        updatedAccount.sortOrder = Int(sortOrderText) ?? 0
        updatedAccount.updatedAt = Account.makeTimestamp()

        do {
            try accountRepository.updateAccount(updatedAccount)
            return accountID
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    private func fail(_ message: String) throws -> Int64 {
        errorMessage = message
        throw EditAccountError.validationFailed(message)
    }

    private func parseOpeningBalance() throws -> Double? {
        let trimmed = openingBalanceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let normalized = trimmed.replacingOccurrences(of: ",", with: ".")
        guard let openingBalance = Double(normalized) else {
            errorMessage = "Opening balance must be a valid number."
            throw EditAccountError.validationFailed("Opening balance must be a valid number.")
        }

        return openingBalance
    }

    private func parseCreditLimit() throws -> Double? {
        let trimmed = creditLimitText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let normalized = trimmed.replacingOccurrences(of: ",", with: ".")
        guard let creditLimit = Double(normalized) else {
            errorMessage = "Credit limit must be a valid number."
            throw EditAccountError.validationFailed("Credit limit must be a valid number.")
        }

        guard creditLimit >= 0 else {
            errorMessage = "Credit limit must be zero or greater."
            throw EditAccountError.validationFailed("Credit limit must be zero or greater.")
        }

        return creditLimit
    }

    private func parseCreditAvailabilityWarningPercent() throws -> Double? {
        let trimmed = creditAvailabilityWarningPercentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let normalized = trimmed.replacingOccurrences(of: ",", with: ".")
        guard let warningPercent = Double(normalized) else {
            errorMessage = "Warning threshold must be a valid percentage."
            throw EditAccountError.validationFailed("Warning threshold must be a valid percentage.")
        }

        guard warningPercent >= 0 else {
            errorMessage = "Warning threshold must be zero or greater."
            throw EditAccountError.validationFailed("Warning threshold must be zero or greater.")
        }

        return warningPercent
    }

    var selectedParentAccount: ParentAccountOption? {
        availableParents.first { $0.id == selectedParentAccountID }
    }

    var accumulationCurrencyOptions: [Currency] {
        availableCurrencies
    }

    var isCreditLimitEditable: Bool {
        accountClass == "liability" && Self.creditCardSubtypes.contains(subtype)
    }

    func synchronizeCurrencyWithParent() {
        guard selectedParentAccountID != previousParentAccountID else {
            return
        }

        previousParentAccountID = selectedParentAccountID

        if let parentCurrency = selectedParentAccount?.currency {
            currencyCode = parentCurrency
        }
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

        return components.reversed().joined(separator: " > ")
    }

    private static let creditCardSubtypes: Set<String> = [
        "credit",
        "credit_card"
    ]

    private func isEligibleForAccumulationCurrency() -> Bool {
        guard let accountID = originalAccount.id else {
            return originalAccount.isGroup
        }

        do {
            let hasChildren = try accountRepository.hasChildren(accountID: accountID)
            return originalAccount.isGroup || hasChildren
        } catch {
            return originalAccount.isGroup
        }
    }
}

extension EditAccountViewModel {
    fileprivate static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

enum EditAccountError: Error, LocalizedError {
    case validationFailed(String)

    var errorDescription: String? {
        switch self {
        case .validationFailed(let message):
            return message
        }
    }
}
