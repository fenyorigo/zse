import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct OperationalIssue: Identifiable, Equatable {
    enum Kind: String, Identifiable {
        case fxRefresh
        case recurringGeneration

        var id: String { rawValue }

        var title: String {
            switch self {
            case .fxRefresh:
                return "FX refresh failed"
            case .recurringGeneration:
                return "Recurring generation failed"
            }
        }
    }

    let kind: Kind
    let message: String
    let recordedAt: Date

    var id: Kind { kind }
}

@MainActor
public final class AppState: ObservableObject {
    @Published private(set) var appName = "zse"
    @Published private(set) var appVersion = "Development Build"
    @Published private(set) var databaseStatus = "Ready"
    @Published private(set) var migrationStatus = "Applied"
    @Published private(set) var currencyCount = 0
    @Published private(set) var accountCount = 0
    @Published private(set) var transactionCount = 0
    @Published private(set) var entryCount = 0
    @Published private(set) var partnerCount = 0
    @Published private(set) var latestFxRateDate: String?
    @Published private(set) var lastErrorMessage: String?
    @Published private(set) var lastOperationMessage: String?
    @Published private(set) var lastManualFxRefreshConfirmationMessage: String?
    @Published private(set) var isManualFxRefreshInProgress = false
    @Published private(set) var lastSuccessfulFxRefreshDate: String?
    @Published private(set) var lastFailedFxRefreshAt: Date?
    @Published private(set) var lastFxRefreshErrorMessage: String?
    @Published private(set) var lastSuccessfulRecurringGenerationAt: Date?
    @Published private(set) var lastFailedRecurringGenerationAt: Date?
    @Published private(set) var lastRecurringGenerationErrorMessage: String?
    @Published private(set) var preferredBackupDirectoryPath: String?

    let databaseManager: DatabaseManager
    let accountRepository: AccountRepository
    let appPreferencesRepository: AppPreferencesRepository
    let accountUIPreferenceRepository: AccountUIPreferenceRepository
    let currencyRepository: CurrencyRepository
    let fxRateRepository: FxRateRepository
    let partnerRepository: PartnerRepository
    let recurringRuleRepository: RecurringRuleRepository
    let transactionRepository: TransactionRepository
    let transactionService: TransactionService
    let recurringTransactionService: RecurringTransactionService
    let importService: ImportService
    let zseFlatFileService: ZseFlatFileService
    let fxRateImportService: FxRateImportService
    let rollupValuationService: RollupValuationService
    let accountBalanceChartService: AccountBalanceChartService
    let databaseMaintenanceService: DatabaseMaintenanceService
    private var activeBackupFolderSecurityScopedURL: URL?

    public init() {
        let databaseManager = DatabaseManager.shared
        self.databaseManager = databaseManager
        self.accountRepository = AccountRepository(databaseManager: databaseManager)
        self.appPreferencesRepository = AppPreferencesRepository(databaseManager: databaseManager)
        self.accountUIPreferenceRepository = AccountUIPreferenceRepository(databaseManager: databaseManager)
        self.currencyRepository = CurrencyRepository(databaseManager: databaseManager)
        self.fxRateRepository = FxRateRepository(databaseManager: databaseManager)
        self.partnerRepository = PartnerRepository(databaseManager: databaseManager)
        self.recurringRuleRepository = RecurringRuleRepository(databaseManager: databaseManager)
        self.transactionRepository = TransactionRepository(databaseManager: databaseManager)
        self.transactionService = TransactionService(
            accountRepository: self.accountRepository,
            partnerRepository: self.partnerRepository,
            transactionRepository: self.transactionRepository
        )
        self.recurringTransactionService = RecurringTransactionService(
            accountRepository: self.accountRepository,
            recurringRuleRepository: self.recurringRuleRepository,
            transactionRepository: self.transactionRepository,
            transactionService: self.transactionService
        )
        self.importService = ImportService(
            databaseManager: databaseManager,
            accountRepository: self.accountRepository,
            transactionService: self.transactionService,
            transactionRepository: self.transactionRepository
        )
        self.zseFlatFileService = ZseFlatFileService(
            databaseManager: databaseManager,
            accountRepository: self.accountRepository,
            transactionRepository: self.transactionRepository
        )
        self.fxRateImportService = FxRateImportService(fxRateRepository: self.fxRateRepository)
        self.rollupValuationService = RollupValuationService(fxRateRepository: self.fxRateRepository)
        self.accountBalanceChartService = AccountBalanceChartService(
            databaseManager: databaseManager,
            accountRepository: self.accountRepository
        )
        self.databaseMaintenanceService = DatabaseMaintenanceService(
            databaseManager: databaseManager,
            appPreferencesRepository: self.appPreferencesRepository
        )

        loadAppMetadata()
        loadOperationalMetadata()
        refreshBackupDirectoryPreference()
        refreshDashboard()
        DispatchQueue.main.async { [weak self] in
            self?.validateBackupFolderAccessOnStartup()
        }

        Task {
            await refreshFxRatesOnStartup()
            generateDueRecurringTransactionsOnStartup()
        }
    }

    func refreshDashboard() {
        do {
            migrationStatus = databaseManager.migrationStatus
            currencyCount = try databaseManager.countRows(in: "currencies")
            accountCount = try accountRepository.getAccountCount()
            transactionCount = try transactionRepository.getTransactionCount()
            entryCount = try databaseManager.countRows(in: "entries")
            partnerCount = try databaseManager.countRows(in: "partners")
            latestFxRateDate = try fxRateRepository.latestStoredRateDate()
            databaseStatus = "Ready"
            lastErrorMessage = nil
        } catch {
            databaseStatus = "Error"
            lastErrorMessage = error.localizedDescription
        }
    }

    func revealDatabaseInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([
            URL(fileURLWithPath: databaseManager.databasePath)
        ])
    }

    func revealBackupFolderInFinder() {
        do {
            _ = try ensureBackupFolderAccessForPreferredFolder()
            let backupFolderURL = try databaseMaintenanceService.backupFolderURL()
            NSWorkspace.shared.activateFileViewerSelecting([backupFolderURL])
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func chooseBackupFolderInteractively() {
        let panel = NSOpenPanel()
        panel.title = "Choose Backup Folder"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = try? databaseMaintenanceService.backupFolderURL()

        guard panel.runModal() == .OK, let folderURL = panel.url else {
            return
        }

        do {
            try saveBackupFolderPreference(folderURL)
            preferredBackupDirectoryPath = folderURL.path
            lastOperationMessage = "Backup folder updated."
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    var backupFolderPreferenceText: String {
        if let preferredBackupDirectoryPath,
           !preferredBackupDirectoryPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return preferredBackupDirectoryPath
        }

        do {
            return "Default: \(try databaseMaintenanceService.backupFolderURL().path)"
        } catch {
            return "Default backup folder unavailable"
        }
    }

    @discardableResult
    func createTimestampedBackup() throws -> URL? {
        guard try ensureBackupFolderAccessForPreferredFolder() else {
            throw CocoaError(.fileWriteNoPermission)
        }
        let destinationURL = try databaseMaintenanceService.makeTimestampedBackupURL(prefix: "zse_backup")
        try databaseMaintenanceService.backupDatabase(to: destinationURL)
        lastOperationMessage = "Backup created: \(destinationURL.lastPathComponent)"
        lastErrorMessage = nil
        refreshDashboard()
        return destinationURL
    }

    func pickRestoreBackupURL() -> URL? {
        _ = try? ensureBackupFolderAccessForPreferredFolder()
        let panel = NSOpenPanel()
        panel.title = "Restore Database from Backup"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [UTType(filenameExtension: "sqlite") ?? .data]
        panel.directoryURL = try? databaseMaintenanceService.backupFolderURL()

        return panel.runModal() == .OK ? panel.url : nil
    }

    @discardableResult
    func restoreDatabase(from backupURL: URL) throws -> URL {
        let safetyBackupURL = try databaseMaintenanceService.restoreDatabase(from: backupURL)
        lastOperationMessage = "Database restored. Safety backup created: \(safetyBackupURL.lastPathComponent)"
        lastErrorMessage = nil
        refreshAfterDatabaseMaintenance()
        return safetyBackupURL
    }

    func wipeDatabase(scope: DatabaseWipeScope) throws {
        try databaseMaintenanceService.wipeDatabase(scope: scope)
        lastOperationMessage = "\(scope.title) completed."
        lastErrorMessage = nil
        refreshAfterDatabaseMaintenance()
    }

    func clearOperationMessage() {
        lastOperationMessage = nil
    }

    func clearManualFxRefreshConfirmation() {
        lastManualFxRefreshConfirmationMessage = nil
    }

    func reportError(_ error: Error) {
        lastErrorMessage = error.localizedDescription
    }

    func clearError() {
        lastErrorMessage = nil
    }

    func generateDueRecurringTransactionsOnStartup() {
        generateDueRecurringTransactions(trigger: .startup)
    }

    func generateDueRecurringTransactionsManually() {
        generateDueRecurringTransactions(trigger: .manual)
    }

    func refreshFxRatesManually() async {
        guard !isManualFxRefreshInProgress else {
            return
        }

        isManualFxRefreshInProgress = true
        defer {
            isManualFxRefreshInProgress = false
        }
        await refreshFxRates(trigger: .manual)
    }

    func clearOperationalIssue(_ kind: OperationalIssue.Kind) {
        switch kind {
        case .fxRefresh:
            lastFailedFxRefreshAt = nil
            lastFxRefreshErrorMessage = nil
        case .recurringGeneration:
            lastFailedRecurringGenerationAt = nil
            lastRecurringGenerationErrorMessage = nil
        }
    }

    var operationalIssues: [OperationalIssue] {
        var issues: [OperationalIssue] = []

        if let lastFxRefreshErrorMessage, let lastFailedFxRefreshAt {
            issues.append(
                OperationalIssue(
                    kind: .fxRefresh,
                    message: lastFxRefreshErrorMessage,
                    recordedAt: lastFailedFxRefreshAt
                )
            )
        }

        if let lastRecurringGenerationErrorMessage, let lastFailedRecurringGenerationAt {
            issues.append(
                OperationalIssue(
                    kind: .recurringGeneration,
                    message: lastRecurringGenerationErrorMessage,
                    recordedAt: lastFailedRecurringGenerationAt
                )
            )
        }

        return issues.sorted { $0.recordedAt > $1.recordedAt }
    }

    var fxRatesStatusText: String {
        if let latestFxRateDate {
            return "Rates used from \(latestFxRateDate)"
        }
        return "Rates used from n/a. Waiting for initial FX refresh; mixed-currency balances may be unavailable."
    }

    var fxRefreshStatusText: String {
        if let lastSuccessfulFxRefreshDate {
            return "Last successful FX refresh: \(lastSuccessfulFxRefreshDate)"
        }
        if let lastFailedFxRefreshAt {
            return "FX refresh last failed at \(Self.operationalTimestampFormatter.string(from: lastFailedFxRefreshAt))"
        }
        return "FX refresh has not completed yet"
    }

    var recurringGenerationStatusText: String {
        if let lastSuccessfulRecurringGenerationAt {
            return "Last recurring generation: \(Self.operationalTimestampFormatter.string(from: lastSuccessfulRecurringGenerationAt))"
        }
        if let lastFailedRecurringGenerationAt {
            return "Recurring generation last failed at \(Self.operationalTimestampFormatter.string(from: lastFailedRecurringGenerationAt))"
        }
        return "Recurring generation has not run yet"
    }

    private func generateDueRecurringTransactions(trigger: BackgroundJobTrigger) {
        do {
            let generatedCount = try recurringTransactionService.generateRecurringTransactions(
                through: recurringTransactionService.recurringPreviewHorizonDate()
            )
            lastSuccessfulRecurringGenerationAt = Date()
            lastFailedRecurringGenerationAt = nil
            lastRecurringGenerationErrorMessage = nil

            if trigger == .manual {
                lastOperationMessage = generatedCount == 0
                    ? "No recurring transactions needed generation."
                    : "Generated \(generatedCount) recurring transaction\(generatedCount == 1 ? "" : "s")."
                lastErrorMessage = nil
            }

            refreshDashboard()

            if generatedCount > 0 {
                NotificationCenter.default.post(name: .recurringTransactionsDidGenerate, object: nil)
            }
        } catch {
            lastFailedRecurringGenerationAt = Date()
            lastRecurringGenerationErrorMessage = error.localizedDescription

            if trigger == .manual {
                lastErrorMessage = error.localizedDescription
            }
        }
    }

    func refreshFxRatesOnStartup() async {
        guard shouldAttemptFxRefreshToday() else {
            refreshDashboard()
            return
        }

        await refreshFxRates(trigger: .startup)
    }

    private func refreshFxRates(trigger: BackgroundJobTrigger) async {
        let today = Self.startupRefreshDateFormatter.string(from: Date())

        do {
            if let importedDate = try await fxRateImportService.refreshLatestRelevantRatesIfPossible() {
                recordFxRefreshSuccess(completedOn: today)
                refreshDashboard()
                NotificationCenter.default.post(name: .fxRatesDidRefresh, object: nil)

                if trigger == .manual {
                    let confirmation = "FX rates refreshed from MNB for \(importedDate)."
                    lastOperationMessage = confirmation
                    lastManualFxRefreshConfirmationMessage = confirmation
                    lastErrorMessage = nil
                }
            } else {
                recordFxRefreshSuccess(completedOn: today)
                refreshDashboard()

                if trigger == .manual {
                    let visibleRateDate = latestFxRateDate ?? today
                    let confirmation = "FX rates confirmed for \(visibleRateDate)."
                    lastOperationMessage = confirmation
                    lastManualFxRefreshConfirmationMessage = confirmation
                    lastErrorMessage = nil
                }
            }
        } catch {
            lastFailedFxRefreshAt = Date()
            lastFxRefreshErrorMessage = error.localizedDescription
            refreshDashboard()

            if trigger == .manual {
                lastErrorMessage = error.localizedDescription
            }
        }
    }

    private func loadAppMetadata() {
        let bundle = Bundle.main

        if let displayName = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String,
           !displayName.isEmpty {
            appName = displayName
        } else if let bundleName = bundle.object(forInfoDictionaryKey: kCFBundleNameKey as String) as? String,
                  !bundleName.isEmpty {
            appName = bundleName
        }

        let shortVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let buildVersion = bundle.object(forInfoDictionaryKey: kCFBundleVersionKey as String) as? String

        switch (shortVersion, buildVersion) {
        case let (.some(shortVersion), .some(buildVersion)):
            appVersion = "\(shortVersion) (\(buildVersion))"
        case let (.some(shortVersion), .none):
            appVersion = shortVersion
        case let (.none, .some(buildVersion)):
            appVersion = "Build \(buildVersion)"
        case (.none, .none):
            appVersion = "Development Build"
        }
    }

    private func loadOperationalMetadata() {
        lastSuccessfulFxRefreshDate = UserDefaults.standard.string(
            forKey: Self.lastSuccessfulFxRefreshDateDefaultsKey
        )
    }

    private func refreshBackupDirectoryPreference() {
        preferredBackupDirectoryPath = try? appPreferencesRepository.backupDirectoryPath()
    }

    private func validateBackupFolderAccessOnStartup() {
        guard let preferredBackupDirectoryPath,
              !preferredBackupDirectoryPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        do {
            if try ensureBackupFolderAccessForPreferredFolder() {
                return
            }
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    @discardableResult
    private func ensureBackupFolderAccessIfNeeded() throws -> Bool {
        guard let preferredBackupDirectoryPath,
              !preferredBackupDirectoryPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }

        if activeBackupFolderSecurityScopedURL?.path == preferredBackupDirectoryPath {
            return true
        }

        guard let bookmarkData = try appPreferencesRepository.backupDirectoryBookmarkData() else {
            return false
        }

        var bookmarkIsStale = false
        let folderURL = try URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &bookmarkIsStale
        )

        if let activeBackupFolderSecurityScopedURL {
            activeBackupFolderSecurityScopedURL.stopAccessingSecurityScopedResource()
            self.activeBackupFolderSecurityScopedURL = nil
        }

        guard folderURL.startAccessingSecurityScopedResource() else {
            return false
        }

        activeBackupFolderSecurityScopedURL = folderURL

        if bookmarkIsStale {
            try saveBackupFolderPreference(folderURL)
        }

        return true
    }

    @discardableResult
    private func ensureBackupFolderAccessForPreferredFolder() throws -> Bool {
        guard let preferredBackupDirectoryPath,
              !preferredBackupDirectoryPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return true
        }

        if try ensureBackupFolderAccessIfNeeded() {
            return true
        }

        guard requestBackupFolderAccessForSavedPreference() else {
            return false
        }

        return try ensureBackupFolderAccessIfNeeded()
    }

    @discardableResult
    private func requestBackupFolderAccessForSavedPreference() -> Bool {
        let panel = NSOpenPanel()
        panel.title = "Grant Access to Backup Folder"
        panel.message = "Zse needs permission to access the configured backup folder after app restart."
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true

        if let preferredBackupDirectoryPath,
           !preferredBackupDirectoryPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            panel.directoryURL = URL(fileURLWithPath: preferredBackupDirectoryPath, isDirectory: true)
        }

        guard panel.runModal() == .OK, let folderURL = panel.url else {
            lastErrorMessage = "Backup folder access was not granted. Backups to the configured folder are unavailable until access is granted."
            return false
        }

        do {
            try saveBackupFolderPreference(folderURL)
            preferredBackupDirectoryPath = folderURL.path
            lastOperationMessage = "Backup folder access granted."
            lastErrorMessage = nil
            return true
        } catch {
            lastErrorMessage = error.localizedDescription
            return false
        }
    }

    private func saveBackupFolderPreference(_ folderURL: URL) throws {
        let bookmarkData = try folderURL.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )

        if let activeBackupFolderSecurityScopedURL {
            activeBackupFolderSecurityScopedURL.stopAccessingSecurityScopedResource()
            self.activeBackupFolderSecurityScopedURL = nil
        }

        guard folderURL.startAccessingSecurityScopedResource() else {
            throw CocoaError(.fileReadNoPermission)
        }

        activeBackupFolderSecurityScopedURL = folderURL
        try appPreferencesRepository.setBackupDirectory(path: folderURL.path, bookmarkData: bookmarkData)
    }

    private func shouldAttemptFxRefreshToday() -> Bool {
        if latestFxRateDate == nil {
            return true
        }

        let today = Self.startupRefreshDateFormatter.string(from: Date())
        return lastSuccessfulFxRefreshDate != today
    }

    private func recordFxRefreshSuccess(completedOn date: String) {
        lastSuccessfulFxRefreshDate = date
        lastFailedFxRefreshAt = nil
        lastFxRefreshErrorMessage = nil
        UserDefaults.standard.set(date, forKey: Self.lastSuccessfulFxRefreshDateDefaultsKey)
    }

    private func refreshAfterDatabaseMaintenance() {
        refreshDashboard()
        NotificationCenter.default.post(name: .databaseDidChange, object: nil)
    }

    private static let lastSuccessfulFxRefreshDateDefaultsKey = "last_successful_fx_refresh_date"

    private static let startupRefreshDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let operationalTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

private enum BackgroundJobTrigger {
    case startup
    case manual
}

extension Notification.Name {
    static let fxRatesDidRefresh = Notification.Name("fxRatesDidRefresh")
    static let recurringTransactionsDidGenerate = Notification.Name("recurringTransactionsDidGenerate")
    static let databaseDidChange = Notification.Name("databaseDidChange")
    static let openDatabaseMaintenanceSheet = Notification.Name("openDatabaseMaintenanceSheet")
    static let openDeveloperStatusSheet = Notification.Name("openDeveloperStatusSheet")
    static let openNewAccountSheet = Notification.Name("openNewAccountSheet")
    static let openEditAccountSheet = Notification.Name("openEditAccountSheet")
    static let requestDeleteAccount = Notification.Name("requestDeleteAccount")
    static let openNewTransactionSheet = Notification.Name("openNewTransactionSheet")
    static let openNewRecurringSheet = Notification.Name("openNewRecurringSheet")
    static let generateDueRecurringTransactions = Notification.Name("generateDueRecurringTransactions")
    static let openImportTransactionsSheet = Notification.Name("openImportTransactionsSheet")
    static let openExportTransactionsSheet = Notification.Name("openExportTransactionsSheet")
}
