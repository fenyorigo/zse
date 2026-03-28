import SwiftUI

struct ContentView: View {
    private struct ActiveAlert: Identifiable {
        enum Kind {
            case accountDeletionError
            case operationError
            case fxRefreshSuccess
        }

        let kind: Kind
        let title: String
        let message: String

        var id: String { title + message }
    }

    @EnvironmentObject private var appState: AppState
    @StateObject private var sidebarViewModel: AccountSidebarViewModel
    @StateObject private var accountDetailViewModel: AccountDetailViewModel
    @State private var selectedSidebarItem: SidebarSelection?
    @State private var activeAlert: ActiveAlert?
    @State private var isShowingFxRefreshProgress = false
    @State private var isShowingDeveloperStatus = false
    @State private var isShowingDatabaseMaintenance = false
    @State private var isShowingNewAccountSheet = false
    @State private var isShowingEditAccountSheet = false
    @State private var isShowingNewTransactionSheet = false
    @State private var isShowingImportTransactionsSheet = false
    @State private var isShowingExportTransactionsSheet = false
    @State private var isShowingRecurringRuleSheet = false
    @State private var isShowingDeleteAccountConfirmation = false
    @State private var accountDeletionErrorMessage: String?

    init() {
        let accountRepository = AccountRepository(databaseManager: DatabaseManager.shared)
        let fxRateRepository = FxRateRepository(databaseManager: DatabaseManager.shared)
        let partnerRepository = PartnerRepository(databaseManager: DatabaseManager.shared)
        let transactionRepository = TransactionRepository(databaseManager: DatabaseManager.shared)
        let transactionService = TransactionService(
            accountRepository: accountRepository,
            partnerRepository: partnerRepository,
            transactionRepository: transactionRepository
        )
        let rollupValuationService = RollupValuationService(fxRateRepository: fxRateRepository)
        _sidebarViewModel = StateObject(
            wrappedValue: AccountSidebarViewModel(
                accountRepository: accountRepository,
                valuationService: rollupValuationService
            )
        )
        _accountDetailViewModel = StateObject(
            wrappedValue: AccountDetailViewModel(
                accountRepository: accountRepository,
                transactionRepository: transactionRepository,
                transactionService: transactionService
            )
        )
    }

    var body: some View {
        observedContent
    }

    private var baseContent: some View {
        mainLayout
            .navigationTitle("")
            .confirmationDialog(
                "Delete Account?",
                isPresented: $isShowingDeleteAccountConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete Account", role: .destructive) {
                    deleteSelectedAccount()
                }
            } message: {
                Text("This only works when the account has no child accounts and no transactions.")
            }
            .alert(item: $activeAlert) { alert in
                Alert(
                    title: Text(alert.title),
                    message: Text(alert.message),
                    dismissButton: .cancel(Text("OK")) {
                        dismissAlert(alert.kind)
                    }
                )
            }
    }

    private var sheetContent: some View {
        baseContent
            .sheet(isPresented: $isShowingFxRefreshProgress) {
                fxRefreshProgressSheet
                    .interactiveDismissDisabled()
            }
            .sheet(isPresented: $isShowingDeveloperStatus) {
                DeveloperStatusView()
                    .environmentObject(appState)
            }
            .sheet(isPresented: $isShowingDatabaseMaintenance) {
                DatabaseMaintenanceSheet {
                    scheduleReloadContent()
                }
                .environmentObject(appState)
            }
            .sheet(isPresented: $isShowingNewAccountSheet) {
                newAccountSheet
            }
            .sheet(isPresented: $isShowingEditAccountSheet) {
                editAccountSheet
            }
            .sheet(isPresented: $isShowingNewTransactionSheet) {
                newTransactionSheet
            }
            .sheet(isPresented: $isShowingImportTransactionsSheet) {
                importTransactionsSheet
            }
            .sheet(isPresented: $isShowingExportTransactionsSheet) {
                exportTransactionsSheet
            }
            .sheet(isPresented: $isShowingRecurringRuleSheet) {
                recurringRuleSheet
            }
    }

    private var alertObservedContent: some View {
        sheetContent
            .onChange(of: selectedSidebarItem) { _, newSelection in
                accountDetailViewModel.setSelection(
                    newSelection,
                    account: sidebarViewModel.account(for: newSelection)
                )
            }
            .onChange(of: accountDeletionErrorMessage) { _, newValue in
                guard let newValue, !newValue.isEmpty else {
                    return
                }
                activeAlert = ActiveAlert(
                    kind: .accountDeletionError,
                    title: "Could Not Delete Account",
                    message: newValue
                )
            }
            .onChange(of: appState.lastErrorMessage) { _, newValue in
                guard let newValue, !newValue.isEmpty else {
                    return
                }
                activeAlert = ActiveAlert(
                    kind: .operationError,
                    title: "Operation Failed",
                    message: newValue
                )
            }
            .onChange(of: appState.lastManualFxRefreshConfirmationMessage) { _, newValue in
                guard let newValue, !newValue.isEmpty else {
                    return
                }
                activeAlert = ActiveAlert(
                    kind: .fxRefreshSuccess,
                    title: "FX Refresh Complete",
                    message: newValue
                )
            }
            .onChange(of: appState.isManualFxRefreshInProgress) { _, newValue in
                isShowingFxRefreshProgress = newValue
            }
    }

    private var observedContent: some View {
        alertObservedContent
            .onReceive(NotificationCenter.default.publisher(for: .fxRatesDidRefresh)) { _ in
                scheduleReloadContent()
            }
            .onReceive(NotificationCenter.default.publisher(for: .recurringTransactionsDidGenerate)) { _ in
                scheduleReloadContent()
            }
            .onReceive(NotificationCenter.default.publisher(for: .databaseDidChange)) { _ in
                scheduleReloadContent()
            }
            .onReceive(NotificationCenter.default.publisher(for: .openDatabaseMaintenanceSheet)) { _ in
                isShowingDatabaseMaintenance = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .openDeveloperStatusSheet)) { _ in
                isShowingDeveloperStatus = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .openNewAccountSheet)) { _ in
                isShowingNewAccountSheet = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .openEditAccountSheet)) { _ in
                if accountDetailViewModel.currentSelectedAccount != nil {
                    isShowingEditAccountSheet = true
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .requestDeleteAccount)) { _ in
                if accountDetailViewModel.currentSelectedAccount != nil {
                    isShowingDeleteAccountConfirmation = true
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .openNewTransactionSheet)) { _ in
                if accountDetailViewModel.currentPostableAccount != nil {
                    isShowingNewTransactionSheet = true
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .openImportTransactionsSheet)) { _ in
                isShowingImportTransactionsSheet = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .openExportTransactionsSheet)) { _ in
                isShowingExportTransactionsSheet = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .openNewRecurringSheet)) { _ in
                isShowingRecurringRuleSheet = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .generateDueRecurringTransactions)) { _ in
                appState.generateDueRecurringTransactionsManually()
                scheduleReloadContent()
            }
            .task {
                scheduleReloadContent()
            }
    }

    private var mainLayout: some View {
        VStack(spacing: 0) {
            NavigationSplitView {
                AccountSidebarView(
                    viewModel: sidebarViewModel,
                    selection: $selectedSidebarItem
                )
                .navigationSplitViewColumnWidth(min: 250, ideal: 300)
                .toolbar {
                    ToolbarItem {
                        Button("Refresh") {
                            scheduleReloadContent()
                        }
                    }
                    ToolbarItem {
                        Toggle("Show Hidden", isOn: Binding(
                            get: { sidebarViewModel.showHiddenAccounts },
                            set: { sidebarViewModel.setShowHiddenAccounts($0) }
                        ))
                    }
                }
            } detail: {
                AccountDetailView(viewModel: accountDetailViewModel) {
                    isShowingEditAccountSheet = true
                } onDeleteAccount: {
                    isShowingDeleteAccountConfirmation = true
                } onTransactionUpdated: {
                    scheduleReloadContent()
                }
            }

            Divider()

            VStack(spacing: 0) {
                if let lastOperationMessage = appState.lastOperationMessage, !lastOperationMessage.isEmpty {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)

                        Text(lastOperationMessage)
                            .font(.footnote)
                            .foregroundStyle(.primary)

                        Spacer()

                        Button("Dismiss") {
                            appState.clearOperationMessage()
                        }
                        .controlSize(.small)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)

                    Divider()
                }

                if !appState.operationalIssues.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(appState.operationalIssues) { issue in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(issue.kind.title)
                                        .font(.footnote.weight(.semibold))
                                    Text(issue.message)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                if issue.kind == .fxRefresh {
                                    Button("Retry FX Now") {
                                        Task {
                                            await appState.refreshFxRatesManually()
                                        }
                                    }
                                    .controlSize(.small)
                                }

                                Button("Dismiss") {
                                    appState.clearOperationalIssue(issue.kind)
                                }
                                .controlSize(.small)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)

                    Divider()
                }

                HStack {
                    Text(appState.fxRatesStatusText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
            .background(.bar)
        }
    }

    private var fxRefreshProgressSheet: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)

            Text("Rates being refreshed")
                .font(.headline)

            Text("Please wait while zsé downloads the latest MNB rates.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(width: 320)
    }

    private var newAccountSheet: some View {
        NewAccountSheet(
            viewModel: NewAccountViewModel(
                accountRepository: appState.accountRepository,
                currencyRepository: appState.currencyRepository
            )
        ) { accountID in
            scheduleReloadContent()
            if let selection = sidebarViewModel.selectionForAccount(id: accountID) {
                selectedSidebarItem = selection
            }
        }
    }

    @ViewBuilder
    private var editAccountSheet: some View {
        if let account = accountDetailViewModel.currentSelectedAccount {
            EditAccountSheet(
                viewModel: EditAccountViewModel(
                    account: account,
                    accountRepository: appState.accountRepository,
                    currencyRepository: appState.currencyRepository
                )
            ) { accountID in
                scheduleReloadContent()
                if let selection = sidebarViewModel.selectionForAccount(id: accountID) {
                    selectedSidebarItem = selection
                }
            }
        }
    }

    @ViewBuilder
    private var newTransactionSheet: some View {
        if let currentAccount = accountDetailViewModel.currentPostableAccount {
            NewTransactionSheet(
                viewModel: NewTransactionViewModel(
                    currentAccount: currentAccount,
                    accountRepository: appState.accountRepository,
                    transactionService: appState.transactionService
                )
            ) { transactionID in
                scheduleReloadContent(selecting: transactionID)
            }
        }
    }

    private var recurringRuleSheet: some View {
        RecurringRuleEditorSheet(
            viewModel: RecurringRuleEditorViewModel(
                accountRepository: appState.accountRepository,
                recurringService: appState.recurringTransactionService
            )
        ) {
            appState.generateDueRecurringTransactionsManually()
            scheduleReloadContent()
        }
    }

    private var importTransactionsSheet: some View {
        ImportTransactionsSheet(
            viewModel: ImportViewModel(importService: appState.importService)
        ) {
            scheduleReloadContent()
        }
    }

    private var exportTransactionsSheet: some View {
        ExportTransactionsSheet(
            selectedAccount: accountDetailViewModel.currentSelectedAccount
        )
        .environmentObject(appState)
    }

    private func reloadContent() {
        appState.refreshDashboard()
        sidebarViewModel.reload()
        clearInvalidSelection()
        accountDetailViewModel.setSelection(
            selectedSidebarItem,
            account: sidebarViewModel.account(for: selectedSidebarItem)
        )
    }

    private func scheduleReloadContent(selecting transactionID: Int64? = nil) {
        DispatchQueue.main.async {
            reloadContent()
            if let transactionID {
                accountDetailViewModel.reloadCurrentAccount(selecting: transactionID)
            }
        }
    }

    private func clearInvalidSelection() {
        guard sidebarViewModel.account(for: selectedSidebarItem) == nil else {
            return
        }

        selectedSidebarItem = nil
    }

    private func deleteSelectedAccount() {
        do {
            try accountDetailViewModel.deleteSelectedAccount()
            selectedSidebarItem = nil
            reloadContent()
        } catch {
            accountDeletionErrorMessage = error.localizedDescription
        }
    }

    private func dismissAlert(_ kind: ActiveAlert.Kind) {
        activeAlert = nil

        switch kind {
        case .accountDeletionError:
            accountDeletionErrorMessage = nil
        case .operationError:
            appState.clearError()
        case .fxRefreshSuccess:
            appState.clearManualFxRefreshConfirmation()
        }
    }
}
