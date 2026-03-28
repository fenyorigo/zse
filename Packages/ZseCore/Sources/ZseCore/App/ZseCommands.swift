import SwiftUI

public struct ZseCommands: Commands {
    @ObservedObject private var appState: AppState

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Back Up Database") {
                do {
                    _ = try appState.createTimestampedBackup()
                } catch {
                    appState.reportError(error)
                }
            }

            Button("Restore Database...") {
                guard let backupURL = appState.pickRestoreBackupURL() else {
                    return
                }

                do {
                    _ = try appState.restoreDatabase(from: backupURL)
                } catch {
                    appState.reportError(error)
                }
            }
        }

        CommandMenu("Database") {
            Button("Refresh FX Rates Now") {
                Task {
                    await appState.refreshFxRatesManually()
                }
            }

            Divider()

            Button("Database Maintenance...") {
                NotificationCenter.default.post(name: .openDatabaseMaintenanceSheet, object: nil)
            }

            Divider()

            Button("Reveal Database in Finder") {
                appState.revealDatabaseInFinder()
            }

            Button("Reveal Backup Folder in Finder") {
                appState.revealBackupFolderInFinder()
            }
        }

        CommandMenu("Accounts") {
            Button("Add Account") {
                NotificationCenter.default.post(name: .openNewAccountSheet, object: nil)
            }

            Button("Edit Account") {
                NotificationCenter.default.post(name: .openEditAccountSheet, object: nil)
            }

            Button("Delete Account") {
                NotificationCenter.default.post(name: .requestDeleteAccount, object: nil)
            }
        }

        CommandMenu("Transactions") {
            Button("Add Transaction") {
                NotificationCenter.default.post(name: .openNewTransactionSheet, object: nil)
            }

            Button("Import Transactions...") {
                NotificationCenter.default.post(name: .openImportTransactionsSheet, object: nil)
            }

            Button("Export Transactions...") {
                NotificationCenter.default.post(name: .openExportTransactionsSheet, object: nil)
            }

            Button("New Recurring Transaction") {
                NotificationCenter.default.post(name: .openNewRecurringSheet, object: nil)
            }

            Button("Generate Due Recurring Transactions") {
                NotificationCenter.default.post(name: .generateDueRecurringTransactions, object: nil)
            }
        }

        CommandMenu("Developer") {
            Button("Developer Status") {
                NotificationCenter.default.post(name: .openDeveloperStatusSheet, object: nil)
            }
        }
    }
}
