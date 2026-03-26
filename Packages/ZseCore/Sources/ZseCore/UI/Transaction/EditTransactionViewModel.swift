import Foundation

@MainActor
final class EditTransactionViewModel: ObservableObject {
    struct CounterpartOption: Identifiable, Hashable {
        let id: Int64
        let fullPath: String
        let accountClass: String
        let currency: String

        var displayName: String {
            "\(fullPath) • \(accountClass.capitalized) • \(currency)"
        }
    }

    @Published var date: Date
    @Published var descriptionText: String
    @Published var state: String
    @Published var transactionType: TransactionService.EditableTransactionType
    @Published var selectedCounterpartAccountID: Int64?
    @Published var currentAmountText: String
    @Published var counterpartAmountText: String
    @Published private(set) var errorMessage: String?
    @Published private(set) var isSaving = false

    let currentAccountName: String
    let currentCurrency: String
    let incomeOptions: [CounterpartOption]
    let expenseOptions: [CounterpartOption]
    let transferOptions: [CounterpartOption]

    private let saveHandler: (
        _ txnDate: String,
        _ description: String?,
        _ state: String,
        _ type: TransactionService.EditableTransactionType,
        _ counterpartAccountID: Int64?,
        _ currentAmount: Double?,
        _ counterpartAmount: Double?
    ) throws -> Void
    private let deleteHandler: () throws -> Void

    init(
        transactionDetail: TransactionDetail,
        transactionType: TransactionService.EditableTransactionType,
        currentAccountName: String,
        currentCurrency: String,
        currentAmount: Double,
        counterpartAmount: Double,
        incomeOptions: [CounterpartOption],
        expenseOptions: [CounterpartOption],
        transferOptions: [CounterpartOption],
        selectedCounterpartAccountID: Int64?,
        saveHandler: @escaping (
            _ txnDate: String,
            _ description: String?,
            _ state: String,
            _ type: TransactionService.EditableTransactionType,
            _ counterpartAccountID: Int64?,
            _ currentAmount: Double?,
            _ counterpartAmount: Double?
        ) throws -> Void,
        deleteHandler: @escaping () throws -> Void
    ) {
        let combinedOptions = incomeOptions + expenseOptions + transferOptions

        self.date = Self.dateFormatter.date(from: transactionDetail.txnDate) ?? Date()
        self.descriptionText = transactionDetail.description ?? ""
        self.state = transactionDetail.state
        self.transactionType = transactionType
        self.currentAccountName = currentAccountName
        self.currentCurrency = currentCurrency
        self.currentAmountText = Self.formattedAmount(currentAmount)
        self.counterpartAmountText = Self.formattedAmount(counterpartAmount)
        self.incomeOptions = incomeOptions
        self.expenseOptions = expenseOptions
        self.transferOptions = transferOptions
        self.selectedCounterpartAccountID = combinedOptions.contains(where: { $0.id == selectedCounterpartAccountID })
            ? selectedCounterpartAccountID
            : nil
        self.saveHandler = saveHandler
        self.deleteHandler = deleteHandler
        synchronizeCounterpartSelection()
    }

    func save() throws {
        errorMessage = nil
        isSaving = true
        defer { isSaving = false }

        do {
            try saveHandler(
                Self.dateFormatter.string(from: date),
                normalized(descriptionText),
                state,
                transactionType,
                selectedCounterpartAccountID,
                parsedCurrentAmount(),
                parsedCounterpartAmount()
            )
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    func deleteTransaction() throws {
        errorMessage = nil
        isSaving = true
        defer { isSaving = false }

        do {
            try deleteHandler()
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    var typeOptions: [TransactionService.EditableTransactionType] {
        TransactionService.EditableTransactionType.allCases
    }

    var counterpartOptions: [CounterpartOption] {
        switch transactionType {
        case .deposit:
            return incomeOptions
        case .spending:
            return expenseOptions
        case .transfer:
            return transferOptions
        }
    }

    var counterpartLabel: String {
        switch transactionType {
        case .deposit:
            return "Income Category"
        case .spending:
            return "Expense Category"
        case .transfer:
            return "Transfer Account"
        }
    }

    var isCounterpartEditable: Bool {
        !counterpartOptions.isEmpty
    }

    var isCrossCurrencyTransfer: Bool {
        guard transactionType == .transfer,
              let counterpartCurrency else {
            return false
        }
        return counterpartCurrency != currentCurrency
    }

    var counterpartCurrency: String? {
        counterpartOptions.first { $0.id == selectedCounterpartAccountID }?.currency
    }

    var canDelete: Bool {
        state == "uncleared" && !isSaving
    }

    func transactionTypeDidChange() {
        synchronizeCounterpartSelection()
    }

    func counterpartDidChange() {
        synchronizeCounterpartSelection()
    }

    private func normalized(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func synchronizeCounterpartSelection() {
        if !counterpartOptions.contains(where: { $0.id == selectedCounterpartAccountID }) {
            selectedCounterpartAccountID = counterpartOptions.first?.id
        }
    }

    private var allOptions: [CounterpartOption] {
        incomeOptions + expenseOptions + transferOptions
    }

    private func parsedCurrentAmount() throws -> Double? {
        guard let amount = Double(currentAmountText.replacingOccurrences(of: ",", with: ".")) else {
            errorMessage = transactionType == .transfer
                ? "Enter a valid amount for \(currentAccountName)."
                : "Enter a valid amount."
            throw NewTransactionError.validationFailed(errorMessage ?? "")
        }
        guard amount > 0 else {
            errorMessage = "Amount must be greater than zero."
            throw NewTransactionError.validationFailed(errorMessage ?? "")
        }
        return amount
    }

    private func parsedCounterpartAmount() throws -> Double? {
        guard transactionType == .transfer else {
            return nil
        }

        if !isCrossCurrencyTransfer {
            return try parsedCurrentAmount()
        }

        guard let amount = Double(counterpartAmountText.replacingOccurrences(of: ",", with: ".")) else {
            errorMessage = "Enter a valid amount for the transfer account."
            throw NewTransactionError.validationFailed(errorMessage ?? "")
        }
        guard amount > 0 else {
            errorMessage = "Amount must be greater than zero."
            throw NewTransactionError.validationFailed(errorMessage ?? "")
        }
        return amount
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
