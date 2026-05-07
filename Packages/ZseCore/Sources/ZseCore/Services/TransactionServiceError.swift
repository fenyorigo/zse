import Foundation

enum TransactionServiceError: Error, LocalizedError {
    case invalidState(String)
    case invalidAmount(Double)
    case duplicateAccounts
    case nonLeafAccountNotPostable(Int64)
    case notEnoughEntries
    case mismatchedCurrencies
    case unbalancedEntries(Double)
    case accountNotFound(Int64)
    case groupAccountNotPostable(Int64)
    case accountCurrencyMismatch(accountID: Int64, accountCurrency: String, entryCurrency: String)
    case invalidCounterpartClass(expected: String, actual: String)
    case unsupportedTransactionEdit
    case transactionDoesNotBelongToSelectedAccount
    case sameCurrencyTransferAmountMismatch
    case missingAmountForTransactionType(TransactionService.EditableTransactionType)
    case missingTargetAmountForCrossCurrencyTransfer
    case crossCurrencyRequiresExactlyTwoEntries
    case onlyUnclearedTransactionsCanBeDeleted

    var errorDescription: String? {
        switch self {
        case .invalidState(let state):
            return "Invalid transaction state: \(state)"
        case .invalidAmount:
            return "Amount must be greater than zero."
        case .duplicateAccounts:
            return "Current and counterpart accounts must be different."
        case .nonLeafAccountNotPostable(let accountID):
            return "Accounts with child accounts cannot be posted to: \(accountID)"
        case .notEnoughEntries:
            return "A transaction must contain at least two entries."
        case .mismatchedCurrencies:
            return "All entries must currently use the same currency."
        case .unbalancedEntries(let total):
            return "Entry amounts must sum to zero. Current total: \(total)"
        case .accountNotFound(let accountID):
            return "Referenced account does not exist: \(accountID)"
        case .groupAccountNotPostable(let accountID):
            return "Group accounts are structural and cannot be posted to: \(accountID)"
        case .accountCurrencyMismatch(let accountID, let accountCurrency, let entryCurrency):
            return "Account \(accountID) uses \(accountCurrency), but the entry uses \(entryCurrency)."
        case .invalidCounterpartClass(let expected, let actual):
            return "Expected a \(expected) category account, but found \(actual)."
        case .unsupportedTransactionEdit:
            return "Only simple two-entry transactions can be recategorized right now."
        case .transactionDoesNotBelongToSelectedAccount:
            return "The selected transaction does not have a simple posting for the current account."
        case .sameCurrencyTransferAmountMismatch:
            return "Same-currency transfers must use the same amount on both sides."
        case .missingAmountForTransactionType(let type):
            return "\(type.rawValue.capitalized) transactions require an amount."
        case .missingTargetAmountForCrossCurrencyTransfer:
            return "Cross-currency transfers require a target amount."
        case .crossCurrencyRequiresExactlyTwoEntries:
            return "Cross-currency transfers must currently contain exactly two entries."
        case .onlyUnclearedTransactionsCanBeDeleted:
            return "Only uncleared transactions can be deleted. Change the status back to uncleared first."
        }
    }
}
