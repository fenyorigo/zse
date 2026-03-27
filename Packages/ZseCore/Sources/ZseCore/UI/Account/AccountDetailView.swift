import SwiftUI

struct AccountDetailView: View {
    private enum TransactionStatusFilter: String, CaseIterable, Identifiable {
        case all
        case clearedOnly
        case pendingOnly
        case hideCleared

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all:
                return "All"
            case .clearedOnly:
                return "Cleared Only"
            case .pendingOnly:
                return "Pending Only"
            case .hideCleared:
                return "Hide Cleared"
            }
        }
    }

    private struct AccountFilterState {
        var statusFilter: TransactionStatusFilter = .all
        var selectedPartnerName = "__all_partners__"
        var selectedCategoryName = "__all_categories__"
        var searchText = ""
        var includeProjectedRecurring = true
    }

    private struct CreditCardAvailabilitySummary {
        let creditLimit: Double?
        let availableBeforeNextReimbursement: Double?
        let nextReimbursementDate: String?
    }

    @EnvironmentObject private var appState: AppState
    @ObservedObject var viewModel: AccountDetailViewModel
    @State private var selectedTransactionIDs = Set<Int64>()
    @State private var isShowingTransactionViewSheet = false
    @State private var isShowingEditTransactionSheet = false
    @State private var isShowingBatchDateSheet = false
    @State private var isShowingBatchStatusSheet = false
    @State private var recurringRuleTemplate: RecurringTransactionTemplate?
    @State private var isShowingRecurringRuleSheet = false
    @State private var inlineEditingTransactionID: Int64?
    @State private var inlineAmountText = ""
    @State private var pendingDeleteTransactionIDs = Set<Int64>()
    @State private var transactionSortOrder = AccountDetailView.defaultTransactionSortOrder
    @State private var statusFilter: TransactionStatusFilter = .all
    @State private var filterStateByAccountID: [Int64: AccountFilterState] = [:]
    @State private var selectedPartnerName: String = Self.allPartnersFilterValue
    @State private var selectedCategoryName: String = Self.allCategoriesFilterValue
    @State private var searchText = ""
    @State private var includeProjectedRecurring = true
    @FocusState private var inlineAmountFieldFocused: Bool
    let onEditAccount: () -> Void
    let onDeleteAccount: () -> Void
    let onTransactionUpdated: () -> Void

    var body: some View {
        Group {
            switch viewModel.state {
            case .noneSelected:
                ContentUnavailableView(
                    "Select an account",
                    systemImage: "sidebar.left",
                    description: Text("Choose a leaf account from the sidebar.")
                )
            case .groupingNode(let title):
                groupingNodeView(title: title)
            case .nonPostable(let account):
                nonPostableView(for: account)
            case .postable(let account, let transactions):
                postableAccountView(account: account, transactions: transactions)
            case .failed(let account, let message):
                failedView(account: account, message: message)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            if selectedTransactionIDs.isEmpty {
                inlineEditingTransactionID = nil
            }
        }
        .alert("Could Not Update Transaction", isPresented: Binding(
            get: { viewModel.transactionEditErrorMessage != nil },
            set: { newValue in
                if !newValue {
                    viewModel.transactionEditErrorMessage = nil
                }
            }
        )) {
            Button("OK", role: .cancel) {
                viewModel.transactionEditErrorMessage = nil
            }
        } message: {
            Text(viewModel.transactionEditErrorMessage ?? "")
        }
        .confirmationDialog(
            deleteConfirmationTitle,
            isPresented: Binding(
                get: { !pendingDeleteTransactionIDs.isEmpty },
                set: { newValue in
                    if !newValue {
                        pendingDeleteTransactionIDs = []
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            Button(deleteConfirmationTitle, role: .destructive) {
                confirmDeleteTransactions()
            }
        } message: {
            Text(deleteConfirmationMessage)
        }
        .sheet(isPresented: $isShowingEditTransactionSheet) {
            if let detail = viewModel.currentTransactionDetail {
                EditTransactionSheet(
                    viewModel: EditTransactionViewModel(
                        transactionDetail: detail,
                        transactionType: viewModel.editableTransactionType() ?? .transfer,
                        currentAccountName: viewModel.currentAccountNameForEdit(),
                        currentCurrency: viewModel.currentAccountCurrencyForEdit(),
                        currentAmount: viewModel.currentAmountForEdit(),
                        counterpartAmount: viewModel.counterpartAmountForEdit(),
                        incomeOptions: viewModel.editableIncomeOptions(),
                        expenseOptions: viewModel.editableExpenseOptions(),
                        transferOptions: viewModel.editableTransferOptions(),
                        selectedCounterpartAccountID: viewModel.selectedCounterpartAccountIDForEdit()
                    ) { txnDate, description, state, type, counterpartAccountID, currentAmount, counterpartAmount in
                        try viewModel.updateSelectedTransaction(
                            txnDate: txnDate,
                            description: description,
                            state: state,
                            type: type,
                            counterpartAccountID: counterpartAccountID,
                            currentAmount: currentAmount,
                            counterpartAmount: counterpartAmount
                        )
                        onTransactionUpdated()
                    } deleteHandler: {
                        try viewModel.deleteSelectedTransaction()
                        onTransactionUpdated()
                    }
                )
            }
        }
        .sheet(isPresented: $isShowingTransactionViewSheet) {
            if let detail = viewModel.currentTransactionDetail {
                TransactionViewSheet(
                    detail: detail,
                    inferredType: inferredTransactionTypeLabel()
                )
            }
        }
        .sheet(isPresented: $isShowingRecurringRuleSheet) {
            RecurringRuleEditorSheet(
                viewModel: RecurringRuleEditorViewModel(
                    accountRepository: appState.accountRepository,
                    recurringService: appState.recurringTransactionService,
                    template: recurringRuleTemplate
                )
            ) {
                appState.generateDueRecurringTransactionsManually()
                onTransactionUpdated()
            }
        }
        .sheet(isPresented: $isShowingBatchDateSheet) {
            BatchTransactionDateSheet(initialDate: selectedTransactionDate ?? Date()) { newDate in
                applyBatchDateChange(newDate)
            }
        }
        .sheet(isPresented: $isShowingBatchStatusSheet) {
            BatchTransactionStatusSheet(initialState: selectedTransactionState) { newState in
                applyBatchStatusChange(newState)
            }
        }
    }

    private func groupingNodeView(title: String) -> some View {
        VStack(spacing: 16) {
            Text(title)
                .font(.title3)
                .fontWeight(.semibold)

            Text("This is a grouping node. Select a lowest-level account to view transactions.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func nonPostableView(for account: Account) -> some View {
        VStack(spacing: 16) {
            Text(account.name)
                .font(.title3)
                .fontWeight(.semibold)

            Text("This is a grouping node. Select a lowest-level account to view transactions.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)

            metadataSection(for: account)
                .frame(maxWidth: 420)

            accountActions
                .frame(maxWidth: 420, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func postableAccountView(account: Account, transactions: [TransactionListItem]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Button("View") {
                    isShowingTransactionViewSheet = true
                }
                .controlSize(.small)
                .disabled(!hasSingleSelection)
                .opacity(hasSingleSelection ? 1 : 0)

                Button("Inline Edit") {
                    if let item = selectedTransactionListItem {
                        enterInlineEdit(for: item)
                    }
                }
                .keyboardShortcut("i", modifiers: [.command])
                .controlSize(.small)
                .disabled(!canInlineEdit)
                .opacity(canInlineEdit ? 1 : 0)

                Button("Edit") {
                    isShowingEditTransactionSheet = true
                }
                .controlSize(.small)
                .disabled(!hasSingleSelection)
                .opacity(hasSingleSelection ? 1 : 0)

                Button("Batch Change Date") {
                    isShowingBatchDateSheet = true
                }
                .keyboardShortcut("g", modifiers: [.command])
                .controlSize(.small)
                .disabled(!hasMultipleSelection)
                .opacity(hasMultipleSelection ? 1 : 0)

                Button("Batch Change Status") {
                    isShowingBatchStatusSheet = true
                }
                .controlSize(.small)
                .disabled(!hasMultipleSelection)
                .opacity(hasMultipleSelection ? 1 : 0)

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            filterBar(for: account, transactions: transactions)

            Group {
                if filteredTransactions(transactions).isEmpty {
                    ContentUnavailableView(
                        transactions.isEmpty ? "No transactions for this account yet." : "No transactions match the current filters.",
                        systemImage: "list.bullet.rectangle",
                        description: Text(
                            transactions.isEmpty
                                ? "Transactions will appear here once entries are posted to this account."
                                : "Adjust the filters or search text to see more transactions."
                        )
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Table(
                        of: TransactionListItem.self,
                        selection: $selectedTransactionIDs,
                        sortOrder: $transactionSortOrder
                    ) {
                        TableColumn("Date", value: \.txnDate) { item in
                            dateCell(for: item)
                        }

                        TableColumn("Description", value: \.descriptionText) { item in
                            descriptionCell(for: item)
                        }

                        TableColumn("Partner", value: \.partnerNameText) { item in
                            plainTextCell(item.partnerName ?? "")
                        }

                        TableColumn("Category", value: \.categoryNameText) { item in
                            plainTextCell(item.categoryName ?? "")
                        }

                        TableColumn("Out", value: \.outSortAmount) { item in
                            amountCell(for: item, accountClass: account.class, showInColumn: false)
                        }

                        TableColumn("In", value: \.inSortAmount) { item in
                            amountCell(for: item, accountClass: account.class, showInColumn: true)
                        }

                        TableColumn("State", value: \.state) { item in
                            stateCell(for: item)
                        }

                        TableColumn("Running Balance") { item in
                            amountText(displayRunningBalance(for: item, accountClass: account.class), alignment: .trailing)
                        }
                    } rows: {
                        ForEach(sortedTransactions(transactions)) { item in
                            TableRow(item)
                        }
                    }
                    .controlSize(.small)
                    .font(.system(size: 12))
                    .contextMenu {
                        selectedTransactionContextMenu
                    }
                    .onDeleteCommand {
                        requestDeleteSelectedTransactions()
                    }
                    .onChange(of: selectedTransactionIDs) { _, newValue in
                        deferSelectionChange(to: newValue)
                    }
                    .onChange(of: statusFilter) { _, _ in
                        storeCurrentFilterState()
                        deferVisibleSelectionSync(transactions)
                    }
                    .onChange(of: selectedPartnerName) { _, _ in
                        storeCurrentFilterState()
                        deferVisibleSelectionSync(transactions)
                    }
                    .onChange(of: selectedCategoryName) { _, _ in
                        storeCurrentFilterState()
                        deferVisibleSelectionSync(transactions)
                    }
                    .onChange(of: searchText) { _, _ in
                        storeCurrentFilterState()
                        deferVisibleSelectionSync(transactions)
                    }
                    .onChange(of: includeProjectedRecurring) { _, _ in
                        storeCurrentFilterState()
                        deferVisibleSelectionSync(transactions)
                    }
                    .onChange(of: transactions.map(\.id)) { _, _ in
                        deferVisibleSelectionSync(transactions)
                    }
                }
            }
            .onAppear {
                loadFilterState(for: account.id)
                selectedTransactionIDs = selectionSet(from: viewModel.selectedTransactionID)
                transactionSortOrder = Self.defaultTransactionSortOrder
            }
            .onChange(of: account.id) { _, _ in
                finishInlineEditing(commit: false)
                selectedTransactionIDs = []
                inlineEditingTransactionID = nil
                transactionSortOrder = Self.defaultTransactionSortOrder
                resetFilters(persist: false)
                loadFilterState(for: account.id)
            }
            .onChange(of: viewModel.selectedTransactionID) { _, newValue in
                let expectedSelection = selectionSet(from: newValue)
                if hasSingleSelection && selectedTransactionIDs != expectedSelection {
                    selectedTransactionIDs = expectedSelection
                    finishInlineEditing(commit: false)
                }
            }
            if let creditCardAvailability = creditCardAvailabilitySummary(
                for: account,
                transactions: transactions
            ) {
                Divider()

                HStack(spacing: 12) {
                    compactMetricText(
                        title: "Limit",
                        value: displayCreditLimitText(creditCardAvailability.creditLimit)
                    )
                    compactMetricText(
                        title: "Avail",
                        value: creditCardAvailability.availableBeforeNextReimbursement.map {
                            formattedAccountMetric($0, currency: "HUF")
                        } ?? "N/A"
                    )
                    compactMetricText(
                        title: "Next",
                        value: creditCardAvailability.nextReimbursementDate ?? "N/A"
                    )
                    Spacer()
                }
                .font(.body)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.bar)
            }
        }
    }

    private func creditCardAvailabilitySummary(
        for account: Account,
        transactions: [TransactionListItem]
    ) -> CreditCardAvailabilitySummary? {
        guard account.class == "liability",
              account.subtype == "credit" else {
            return nil
        }

        let orderedTransactions = transactions.sorted(using: Self.defaultTransactionSortOrder)
        let nextReimbursementIndex = orderedTransactions.firstIndex { item in
            item.txnDate >= Self.todayDateString &&
            item.memoSummary == "Hitelkártya visszafizetés" &&
            (displayInAmount(for: item, accountClass: account.class) ?? 0) > 0
        }

        let usedBeforeReimbursement = nextReimbursementIndex.flatMap { index -> Double? in
            guard index > 0 else {
                return nil
            }

            let priorItem = orderedTransactions[index - 1]
            return displayRunningBalance(for: priorItem, accountClass: account.class)
        }

        let availableBeforeNextReimbursement = account.creditLimit.flatMap { creditLimit in
            usedBeforeReimbursement.map { creditLimit - $0 }
        }
        let nextReimbursementDate = nextReimbursementIndex.map { orderedTransactions[$0].txnDate }

        return CreditCardAvailabilitySummary(
            creditLimit: account.creditLimit,
            availableBeforeNextReimbursement: availableBeforeNextReimbursement,
            nextReimbursementDate: nextReimbursementDate
        )
    }

    private func displayOutAmount(for item: TransactionListItem, accountClass: String) -> Double? {
        let displayedAmount = displayedFlowAmount(for: item, accountClass: accountClass)
        return displayedAmount < 0 ? abs(displayedAmount) : nil
    }

    private func displayInAmount(for item: TransactionListItem, accountClass: String) -> Double? {
        let displayedAmount = displayedFlowAmount(for: item, accountClass: accountClass)
        return displayedAmount > 0 ? displayedAmount : nil
    }

    private func displayRunningBalance(for item: TransactionListItem, accountClass: String) -> Double {
        shouldInvertBalanceDisplaySign(for: accountClass) ? -item.runningBalance : item.runningBalance
    }

    private func displayedFlowAmount(for item: TransactionListItem, accountClass: String) -> Double {
        let rawAmount = (item.inAmount ?? 0) - (item.outAmount ?? 0)
        return shouldInvertFlowDisplaySign(for: accountClass) ? -rawAmount : rawAmount
    }

    private func shouldInvertFlowDisplaySign(for accountClass: String) -> Bool {
        accountClass == "income"
    }

    private func shouldInvertBalanceDisplaySign(for accountClass: String) -> Bool {
        accountClass == "income" || accountClass == "liability"
    }

    private func failedView(account: Account?, message: String) -> some View {
        VStack(spacing: 12) {
            Text(account?.name ?? "Account")
                .font(.title3)
                .fontWeight(.semibold)

            Text("Transactions could not be loaded.")
                .foregroundStyle(.secondary)

            Text(message)
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func metadataSection(for account: Account) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            detailRow(title: "Subtype", value: account.subtype)
            detailRow(title: "Currency", value: account.currency)
            detailRow(title: "Account ID", value: "\(account.id ?? 0)")
            detailRow(title: "Posting type", value: account.isGroup ? "Group" : "Postable")
            detailRow(
                title: "Include in net worth",
                value: account.includeInNetWorth ? "Yes" : "No"
            )
        }
    }

    private var accountActions: some View {
        HStack(spacing: 8) {
            Button("Edit Account") {
                onEditAccount()
            }
            .controlSize(.small)

            Button("Delete Account", role: .destructive) {
                onDeleteAccount()
            }
            .disabled(!viewModel.deleteAvailability.isAllowed)
            .controlSize(.small)

            if let message = viewModel.deleteAvailability.message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func detailRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 120, alignment: .leading)
            Text(value.isEmpty ? " " : value)
                .textSelection(.enabled)
                .font(.callout)
        }
    }

    private func detailSubrow(title: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .leading)
            Text(value)
                .textSelection(.enabled)
        }
        .font(.footnote)
    }

    @ViewBuilder
    private func amountText(_ amount: Double?, alignment: Alignment) -> some View {
        Text(amount.map { String(format: "%.2f", $0) } ?? "")
            .frame(maxWidth: .infinity, alignment: alignment)
            .font(.system(.callout, design: .monospaced))
    }

    @ViewBuilder
    private func amountCell(for item: TransactionListItem, accountClass: String, showInColumn: Bool) -> some View {
        if singleSelectedTransactionID == item.id,
           inlineEditingTransactionID == item.id,
           let context = viewModel.inlineAmountEditContext() {
            let displayedAmount = displayedFlowAmount(for: item, accountClass: accountClass)
            let isInColumn = displayedAmount > 0

            if isInColumn == showInColumn {
                HStack(spacing: 4) {
                    TextField("Amount", text: $inlineAmountText)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.small)
                        .focused($inlineAmountFieldFocused)
                        .onSubmit {
                            finishInlineEditing(commit: true)
                        }
                        .onExitCommand {
                            finishInlineEditing(commit: false)
                        }
                    Text(context.currency)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                amountText(nil, alignment: .trailing)
            }
        } else {
            amountText(
                showInColumn
                    ? displayInAmount(for: item, accountClass: accountClass)
                    : displayOutAmount(for: item, accountClass: accountClass),
                alignment: .trailing
            )
        }
    }

    private func formattedAmount(_ amount: Double, currency: String) -> String {
        "\(String(format: "%.2f", amount)) \(currency)"
    }

    private func formattedAccountMetric(_ amount: Double, currency: String) -> String {
        formattedAmount(amount, currency: currency)
    }

    private func displayCreditLimitText(_ creditLimit: Double?) -> String {
        guard let creditLimit, abs(creditLimit) > 0.000001 else {
            return "not set"
        }

        return formattedAccountMetric(creditLimit, currency: "HUF")
    }

    @ViewBuilder
    private func dateCell(for item: TransactionListItem) -> some View {
        if singleSelectedTransactionID == item.id,
           inlineEditingTransactionID == item.id,
           let selectedDate = date(from: item.txnDate) {
            DatePicker(
                "",
                selection: Binding(
                    get: { selectedDate },
                    set: { newValue in
                        viewModel.updateSelectedTransactionDate(newValue)
                        if viewModel.transactionEditErrorMessage == nil {
                            onTransactionUpdated()
                        }
                    }
                ),
                displayedComponents: .date
            )
            .labelsHidden()
            .datePickerStyle(.field)
            .controlSize(.small)
            .frame(width: 118, alignment: .leading)
            .onSubmit {
                finishInlineEditing(commit: true)
            }
        } else {
            plainTextCell(item.txnDate)
        }
    }

    @ViewBuilder
    private func stateCell(for item: TransactionListItem) -> some View {
        if singleSelectedTransactionID == item.id, inlineEditingTransactionID == item.id {
            Picker(
                "",
                selection: Binding(
                    get: { item.state },
                    set: { newValue in
                        viewModel.updateSelectedTransactionState(newValue)
                        if viewModel.transactionEditErrorMessage == nil {
                            onTransactionUpdated()
                        }
                    }
                )
            ) {
                Text("Uncleared").tag("uncleared")
                Text("Pending").tag("reconciling")
                Text("Cleared").tag("cleared")
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .controlSize(.small)
        } else {
            statusBadgeCell(for: item)
        }
    }

    private func plainTextCell(_ value: String) -> some View {
        Text(value)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func statusBadgeCell(for item: TransactionListItem) -> some View {
        let badge = statusBadge(for: item.state)
        let isSelected = selectedTransactionIDs.contains(item.id)
        let badgeColor = item.statusWarningFlag ? Self.warningStatusColor : badge?.color

        if let badge, let badgeColor {
            Text(badge.title)
                .lineLimit(1)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    badgeColor.opacity(isSelected ? 0.55 : 1),
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if item.statusWarningFlag {
            Text(displayTitle(for: item.state))
                .lineLimit(1)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    Self.warningStatusColor.opacity(isSelected ? 0.55 : 1),
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            plainTextCell(displayTitle(for: item.state))
        }
    }

    private func displayTitle(for state: String) -> String {
        switch state {
        case "cleared":
            return "Cleared"
        case "reconciling":
            return "Pending"
        default:
            return "Uncleared"
        }
    }

    private func statusBadge(for state: String) -> (title: String, color: Color)? {
        switch state {
        case "cleared":
            return ("Cleared", Self.clearedStatusColor)
        case "reconciling":
            return ("Pending", Self.pendingStatusColor)
        default:
            return nil
        }
    }

    @ViewBuilder
    private func descriptionCell(for item: TransactionListItem) -> some View {
        HStack(spacing: 6) {
            plainTextCell(item.description ?? "")

            if isProjectedRecurring(item) {
                Text("Projected")
                    .font(.caption2)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .foregroundStyle(.secondary)
                    .background(.quaternary, in: Capsule())
            }
        }
    }

    @ViewBuilder
    private var selectedTransactionContextMenu: some View {
        if hasMultipleSelection {
            Button("Batch Change Date") {
                isShowingBatchDateSheet = true
            }

            Button("Batch Change Status") {
                isShowingBatchStatusSheet = true
            }

            Button("Delete Selected", role: .destructive) {
                requestDeleteSelectedTransactions()
            }
        } else if let item = selectedTransactionListItem {
            Button("View") {
                viewModel.selectTransaction(transactionID: item.id)
                isShowingTransactionViewSheet = true
            }

            Button("Create Recurring from Transaction") {
                createRecurringFromTransaction(item)
            }

            Button("Inline Edit") {
                enterInlineEdit(for: item)
            }

            Button("Edit") {
                openEditSheet(for: item)
            }

            Button("Duplicate Transaction") {
                duplicateTransaction(item)
            }

            Button("Delete Transaction", role: .destructive) {
                pendingDeleteTransactionIDs = [item.id]
            }
            .disabled(item.state != "uncleared")
        }
    }

    private func duplicateTransaction(_ item: TransactionListItem) {
        do {
            finishInlineEditing(commit: false)
            _ = try viewModel.duplicateTransaction(transactionID: item.id)
            inlineEditingTransactionID = nil
            onTransactionUpdated()
        } catch {
            viewModel.transactionEditErrorMessage = error.localizedDescription
        }
    }

    private func confirmDeleteTransactions() {
        guard !pendingDeleteTransactionIDs.isEmpty else {
            return
        }

        do {
            finishInlineEditing(commit: false)
            try viewModel.deleteTransactions(transactionIDs: pendingDeleteTransactionIDs)
            inlineEditingTransactionID = nil
            selectedTransactionIDs = []
            pendingDeleteTransactionIDs = []
            onTransactionUpdated()
        } catch {
            viewModel.transactionEditErrorMessage = error.localizedDescription
        }
    }

    private var selectedTransactionListItem: TransactionListItem? {
        guard case let .postable(_, transactions) = viewModel.state,
              let selectedTransactionID = singleSelectedTransactionID else {
            return nil
        }

        return transactions.first(where: { $0.id == selectedTransactionID })
    }

    private func openEditSheet(for item: TransactionListItem) {
        selectedTransactionIDs = [item.id]
        finishInlineEditing(commit: false)
        viewModel.selectTransaction(transactionID: item.id)
        isShowingEditTransactionSheet = true
    }

    private func inferredTransactionTypeLabel() -> String? {
        viewModel.editableTransactionType()?.rawValue.capitalized
    }

    private func enterInlineEdit(for item: TransactionListItem) {
        selectedTransactionIDs = [item.id]
        viewModel.selectTransaction(transactionID: item.id)
        inlineEditingTransactionID = item.id
        if let context = viewModel.inlineAmountEditContext() {
            inlineAmountText = String(format: "%.2f", context.amount)
            inlineAmountFieldFocused = true
        } else {
            inlineAmountText = ""
            inlineAmountFieldFocused = false
        }
    }

    private func finishInlineEditing(commit: Bool) {
        guard inlineEditingTransactionID != nil else {
            return
        }

        defer {
            inlineEditingTransactionID = nil
            inlineAmountFieldFocused = false
        }

        guard commit else {
            if let context = viewModel.inlineAmountEditContext() {
                inlineAmountText = String(format: "%.2f", context.amount)
            }
            return
        }

        guard viewModel.inlineAmountEditContext() != nil else {
            return
        }

        let normalized = inlineAmountText.replacingOccurrences(of: ",", with: ".")
        guard let amount = Double(normalized), amount > 0 else {
            viewModel.transactionEditErrorMessage = "Amount must be a valid number greater than zero."
            return
        }

        do {
            try viewModel.updateSelectedTransactionAmount(amount)
            inlineAmountText = String(format: "%.2f", amount)
            onTransactionUpdated()
        } catch {
            viewModel.transactionEditErrorMessage = error.localizedDescription
        }
    }

    private func date(from value: String) -> Date? {
        Self.inlineDateFormatter.date(from: value)
    }

    private func createRecurringFromTransaction(_ item: TransactionListItem) {
        guard let currentAccountID = viewModel.currentPostableAccount?.id else {
            return
        }

        do {
            recurringRuleTemplate = try appState.recurringTransactionService.makeTemplateFromTransaction(
                transactionID: item.id,
                currentAccountID: currentAccountID
            )
            isShowingRecurringRuleSheet = true
        } catch {
            viewModel.transactionEditErrorMessage = error.localizedDescription
        }
    }

    private func sortedTransactions(_ transactions: [TransactionListItem]) -> [TransactionListItem] {
        filteredTransactions(transactions).sorted(using: transactionSortOrder)
    }

    private func filteredTransactions(_ transactions: [TransactionListItem]) -> [TransactionListItem] {
        transactions.filter { item in
            matchesProjectedFilter(item)
                && matchesStatusFilter(item)
                && matchesPartnerFilter(item)
                && matchesCategoryFilter(item)
                && matchesSearchFilter(item)
        }
    }

    private func matchesProjectedFilter(_ item: TransactionListItem) -> Bool {
        includeProjectedRecurring || !isProjectedRecurring(item)
    }

    private func matchesStatusFilter(_ item: TransactionListItem) -> Bool {
        switch statusFilter {
        case .all:
            return true
        case .clearedOnly:
            return item.state == "cleared"
        case .pendingOnly:
            return item.state == "reconciling"
        case .hideCleared:
            return item.state == "uncleared" || item.state == "reconciling"
        }
    }

    private func matchesPartnerFilter(_ item: TransactionListItem) -> Bool {
        selectedPartnerName == Self.allPartnersFilterValue || item.partnerName == selectedPartnerName
    }

    private func matchesCategoryFilter(_ item: TransactionListItem) -> Bool {
        selectedCategoryName == Self.allCategoriesFilterValue || item.categoryName == selectedCategoryName
    }

    private func matchesSearchFilter(_ item: TransactionListItem) -> Bool {
        let normalizedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSearch.isEmpty else {
            return true
        }

        let haystack = [
            item.descriptionText,
            item.partnerNameText,
            item.categoryNameText,
            item.memoSummaryText
        ]
            .joined(separator: " ")
            .localizedLowercase

        return haystack.contains(normalizedSearch.localizedLowercase)
    }

    private func isProjectedRecurring(_ item: TransactionListItem) -> Bool {
        item.recurringRuleID != nil && item.txnDate > Self.todayDateString
    }

    @ViewBuilder
    private func filterBar(for account: Account, transactions: [TransactionListItem]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Picker("Status", selection: $statusFilter) {
                    ForEach(TransactionStatusFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)

                Picker("Partner", selection: $selectedPartnerName) {
                    Text("All Partners").tag(Self.allPartnersFilterValue)
                    ForEach(partnerFilterOptions(for: transactions), id: \.self) { partnerName in
                        Text(partnerName).tag(partnerName)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)

                Picker("Category", selection: $selectedCategoryName) {
                    Text("All Categories").tag(Self.allCategoriesFilterValue)
                    ForEach(categoryFilterOptions(for: transactions), id: \.self) { categoryName in
                        Text(categoryName).tag(categoryName)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)

                TextField("Search", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                    .frame(width: 180)

                Toggle("Projected", isOn: $includeProjectedRecurring)
                    .toggleStyle(.checkbox)
                    .controlSize(.small)

                if hasActiveFilters {
                    Button("Clear") {
                        resetFilters()
                    }
                    .controlSize(.small)
                }

                Spacer()
            }

        }
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }

    private func compactMetricText(title: String, value: String) -> some View {
        Text("\(title): \(value)")
            .lineLimit(1)
            .truncationMode(.tail)
    }

    private func partnerFilterOptions(for transactions: [TransactionListItem]) -> [String] {
        Array(
            Set(
                transactions.compactMap(\.partnerName).filter { !$0.isEmpty }
            )
        )
        .sorted { lhs, rhs in
            lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }
    }

    private func categoryFilterOptions(for transactions: [TransactionListItem]) -> [String] {
        Array(
            Set(
                transactions.compactMap(\.categoryName).filter { !$0.isEmpty }
            )
        )
        .sorted { lhs, rhs in
            lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }
    }

    private var singleSelectedTransactionID: Int64? {
        selectedTransactionIDs.count == 1 ? selectedTransactionIDs.first : nil
    }

    private var hasSingleSelection: Bool {
        singleSelectedTransactionID != nil
    }

    private var hasMultipleSelection: Bool {
        selectedTransactionIDs.count > 1
    }

    private var canInlineEdit: Bool {
        hasSingleSelection
    }

    private var selectedTransactionDate: Date? {
        guard let item = selectedTransactionListItem else {
            return nil
        }

        return date(from: item.txnDate)
    }

    private var selectedTransactionState: String {
        selectedTransactionListItem?.state ?? "uncleared"
    }

    private var deleteConfirmationTitle: String {
        let count = pendingDeleteTransactionIDs.count
        return count == 1 ? "Delete 1 transaction?" : "Delete \(count) transactions?"
    }

    private var deleteConfirmationMessage: String {
        if pendingDeleteTransactionIDs.count == 1 {
            return "Deleting a transfer deletes the whole transaction from both sides."
        }

        return "Deleting selected transfers deletes the whole transaction from both sides."
    }

    private func requestDeleteSelectedTransactions() {
        guard !selectedTransactionIDs.isEmpty else {
            return
        }

        pendingDeleteTransactionIDs = selectedTransactionIDs
    }

    private func applyBatchDateChange(_ date: Date) {
        do {
            finishInlineEditing(commit: false)
            try viewModel.updateTransactionDates(transactionIDs: selectedTransactionIDs, to: date)
            inlineEditingTransactionID = nil
            onTransactionUpdated()
        } catch {
            viewModel.transactionEditErrorMessage = error.localizedDescription
        }
    }

    private func applyBatchStatusChange(_ state: String) {
        do {
            finishInlineEditing(commit: false)
            try viewModel.updateTransactionStates(transactionIDs: selectedTransactionIDs, to: state)
            inlineEditingTransactionID = nil
            onTransactionUpdated()
        } catch {
            viewModel.transactionEditErrorMessage = error.localizedDescription
        }
    }

    private func syncInspectorSelection(with transactionIDs: Set<Int64>) {
        if transactionIDs.count == 1, let transactionID = transactionIDs.first {
            viewModel.selectTransaction(transactionID: transactionID)
        } else {
            viewModel.selectTransaction(transactionID: nil)
        }
    }

    private func selectionSet(from transactionID: Int64?) -> Set<Int64> {
        guard let transactionID else {
            return []
        }
        return [transactionID]
    }

    private func storeCurrentFilterState() {
        guard let accountID = viewModel.currentPostableAccount?.id else {
            return
        }

        filterStateByAccountID[accountID] = AccountFilterState(
            statusFilter: statusFilter,
            selectedPartnerName: selectedPartnerName,
            selectedCategoryName: selectedCategoryName,
            searchText: searchText,
            includeProjectedRecurring: includeProjectedRecurring
        )

        try? appState.accountUIPreferenceRepository.saveTransactionStatusFilter(
            accountID: accountID,
            filter: statusFilter.rawValue
        )
    }

    private func loadFilterState(for accountID: Int64?) {
        guard let accountID else {
            statusFilter = .all
            selectedPartnerName = Self.allPartnersFilterValue
            selectedCategoryName = Self.allCategoriesFilterValue
            searchText = ""
            includeProjectedRecurring = true
            return
        }

        let filterState = filterStateByAccountID[accountID] ?? AccountFilterState()
        let savedFilter = try? appState.accountUIPreferenceRepository
            .savedTransactionStatusFilter(accountID: accountID)

        if let savedFilter = savedFilter ?? nil,
           let persistedStatusFilter = TransactionStatusFilter(rawValue: savedFilter) {
            statusFilter = persistedStatusFilter
        } else {
            statusFilter = filterState.statusFilter
        }
        selectedPartnerName = filterState.selectedPartnerName
        selectedCategoryName = filterState.selectedCategoryName
        searchText = filterState.searchText
        includeProjectedRecurring = filterState.includeProjectedRecurring
    }

    private func syncSelectionWithVisibleTransactions(_ transactions: [TransactionListItem]) {
        guard !selectedTransactionIDs.isEmpty else {
            return
        }

        let visibleIDs = Set(filteredTransactions(transactions).map(\.id))
        let visibleSelection = selectedTransactionIDs.intersection(visibleIDs)

        guard visibleSelection != selectedTransactionIDs else {
            return
        }

        finishInlineEditing(commit: false)
        selectedTransactionIDs = visibleSelection
        syncInspectorSelection(with: visibleSelection)
    }

    private func deferSelectionChange(to transactionIDs: Set<Int64>) {
        DispatchQueue.main.async {
            if transactionIDs.count != 1 || inlineEditingTransactionID != transactionIDs.first {
                finishInlineEditing(commit: true)
            }
            syncInspectorSelection(with: transactionIDs)
        }
    }

    private func deferVisibleSelectionSync(_ transactions: [TransactionListItem]) {
        DispatchQueue.main.async {
            syncSelectionWithVisibleTransactions(transactions)
        }
    }

    private func resetFilters(persist: Bool = true) {
        statusFilter = .all
        selectedPartnerName = Self.allPartnersFilterValue
        selectedCategoryName = Self.allCategoriesFilterValue
        searchText = ""
        includeProjectedRecurring = true
        if persist {
            storeCurrentFilterState()
        }
    }

    private var hasActiveFilters: Bool {
        statusFilter != .all
            || selectedPartnerName != Self.allPartnersFilterValue
            || selectedCategoryName != Self.allCategoriesFilterValue
            || !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !includeProjectedRecurring
    }

    private static let inlineDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let allPartnersFilterValue = "__all_partners__"
    private static let allCategoriesFilterValue = "__all_categories__"
    private static let todayDateString = inlineDateFormatter.string(from: Date())
    private static let clearedStatusColor = Color(
        red: 191 / 255,
        green: 229 / 255,
        blue: 168 / 255
    )
    private static let pendingStatusColor = Color(
        red: 227 / 255,
        green: 197 / 255,
        blue: 135 / 255
    )
    private static let warningStatusColor = Color(
        red: 224 / 255,
        green: 112 / 255,
        blue: 112 / 255
    )

    private static let defaultTransactionSortOrder: [KeyPathComparator<TransactionListItem>] = [
        KeyPathComparator(\.txnDate, order: .forward),
        KeyPathComparator(\.createdAt, order: .forward),
        KeyPathComparator(\.transactionID, order: .forward),
        KeyPathComparator(\.firstEntryID, order: .forward)
    ]
}

private struct BatchTransactionDateSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedDate: Date

    let applyHandler: (Date) -> Void

    init(initialDate: Date, applyHandler: @escaping (Date) -> Void) {
        _selectedDate = State(initialValue: initialDate)
        self.applyHandler = applyHandler
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Batch Change Date")
                .font(.title3)
                .fontWeight(.semibold)

            DatePicker(
                "New Date",
                selection: $selectedDate,
                displayedComponents: .date
            )
            .datePickerStyle(.field)

            HStack {
                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Apply") {
                    applyHandler(selectedDate)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 320)
    }
}

private struct BatchTransactionStatusSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedState: String

    let applyHandler: (String) -> Void

    init(initialState: String, applyHandler: @escaping (String) -> Void) {
        _selectedState = State(initialValue: initialState)
        self.applyHandler = applyHandler
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Batch Change Status")
                .font(.title3)
                .fontWeight(.semibold)

            Picker("New Status", selection: $selectedState) {
                Text("Uncleared").tag("uncleared")
                Text("Pending").tag("reconciling")
                Text("Cleared").tag("cleared")
            }
            .pickerStyle(.menu)

            HStack {
                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Apply") {
                    applyHandler(selectedState)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 320)
    }
}

private struct TransactionViewSheet: View {
    @Environment(\.dismiss) private var dismiss

    let detail: TransactionDetail
    let inferredType: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Transaction")
                        .font(.title3)
                        .fontWeight(.semibold)
                    Spacer()
                    Button("Close") {
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)
                }

                VStack(alignment: .leading, spacing: 8) {
                    detailRow(title: "Date", value: detail.txnDate)
                    if let inferredType, !inferredType.isEmpty {
                        detailRow(title: "Type", value: inferredType)
                    }
                    detailRow(title: "Description", value: detail.description ?? "")
                    detailRow(title: "State", value: detail.state.capitalized)
                    detailRow(title: "Transaction ID", value: "\(detail.id)")
                    detailRow(title: "Partner", value: detail.partnerSummary ?? "")
                    detailRow(title: "Memo", value: detail.memoSummary ?? "")
                    detailRow(title: "Created", value: detail.createdAt)
                    detailRow(title: "Updated", value: detail.updatedAt)
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Entries")
                        .font(.headline)

                    ForEach(detail.entries) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(entry.accountName)
                                    .fontWeight(.medium)
                                Spacer()
                                Text("\(String(format: "%.2f", entry.amount)) \(entry.currency)")
                                    .font(.system(.callout, design: .monospaced))
                            }

                            if let partnerName = entry.partnerName, !partnerName.isEmpty {
                                detailSubrow(title: "Partner", value: partnerName)
                            }

                            if let memo = entry.memo, !memo.isEmpty {
                                detailSubrow(title: "Memo", value: memo)
                            }
                        }
                        .padding(.vertical, 4)

                        if entry.id != detail.entries.last?.id {
                            Divider()
                        }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(width: 520, height: 520)
        .controlSize(.small)
    }

    private func detailRow(title: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 120, alignment: .leading)
            Text(value.isEmpty ? " " : value)
                .textSelection(.enabled)
                .font(.callout)
        }
    }

    private func detailSubrow(title: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .leading)
            Text(value)
                .textSelection(.enabled)
        }
        .font(.footnote)
    }
}
