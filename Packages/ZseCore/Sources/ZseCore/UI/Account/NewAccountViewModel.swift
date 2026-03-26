import Foundation

@MainActor
final class NewAccountViewModel: ObservableObject {
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

    @Published var name = ""
    @Published var selectedParentAccountID: Int64?
    @Published var accountClass = "asset"
    @Published var subtype = "bank"
    @Published var currencyCode = "HUF"
    @Published var isGroup = false
    @Published var includeInNetWorth = true
    @Published var openingBalanceText = ""
    @Published var hasOpeningBalanceDate = false
    @Published var openingBalanceDate = Date()
    @Published var sortOrderText = "0"
    @Published private(set) var availableParents: [ParentAccountOption] = []
    @Published private(set) var availableCurrencies: [Currency] = []
    @Published private(set) var errorMessage: String?
    @Published private(set) var isSaving = false

    private let accountRepository: AccountRepository
    private let currencyRepository: CurrencyRepository
    private var previousParentAccountID: Int64?

    init(
        accountRepository: AccountRepository,
        currencyRepository: CurrencyRepository
    ) {
        self.accountRepository = accountRepository
        self.currencyRepository = currencyRepository
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
                guard let accountID = account.id else {
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

            if availableCurrencies.contains(where: { $0.code == "HUF" }) {
                currencyCode = "HUF"
            } else if let firstCurrency = availableCurrencies.first {
                currencyCode = firstCurrency.code
            }

            errorMessage = nil
        } catch {
            availableParents = []
            availableCurrencies = []
            errorMessage = error.localizedDescription
        }
    }

    func save() throws -> Int64 {
        errorMessage = nil

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
        let openingBalanceDateString = hasOpeningBalanceDate
            ? Self.dateFormatter.string(from: openingBalanceDate)
            : nil

        let sortOrder = Int(sortOrderText) ?? 0
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

        var account = Account(
            parentID: selectedParentAccountID,
            name: trimmedName,
            class: accountClass,
            subtype: subtype,
            currency: currencyCode,
            isGroup: isGroup,
            includeInNetWorth: includeInNetWorth,
            openingBalance: openingBalance,
            openingBalanceDate: openingBalanceDateString,
            sortOrder: sortOrder
        )

        do {
            try accountRepository.createAccount(&account)
            guard let accountID = account.id else {
                return try fail("The account could not be created.")
            }
            return accountID
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    private func fail(_ message: String) throws -> Int64 {
        errorMessage = message
        throw NewAccountError.validationFailed(message)
    }

    private func parseOpeningBalance() throws -> Double? {
        let trimmed = openingBalanceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let normalized = trimmed.replacingOccurrences(of: ",", with: ".")
        guard let openingBalance = Double(normalized) else {
            errorMessage = "Opening balance must be a valid number."
            throw NewAccountError.validationFailed("Opening balance must be a valid number.")
        }

        return openingBalance
    }

    var selectedParentAccount: ParentAccountOption? {
        availableParents.first { $0.id == selectedParentAccountID }
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
}

extension NewAccountViewModel {
    fileprivate static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

enum NewAccountError: Error, LocalizedError {
    case validationFailed(String)

    var errorDescription: String? {
        switch self {
        case .validationFailed(let message):
            return message
        }
    }
}
