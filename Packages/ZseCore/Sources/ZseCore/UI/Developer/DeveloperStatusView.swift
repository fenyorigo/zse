import SwiftUI

struct DeveloperStatusView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text(appState.appName)
                    .font(.title)
                    .fontWeight(.semibold)

                Text(appState.appVersion)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Startup")
                    .font(.headline)

                statusRow(title: "Database status", value: appState.databaseStatus)
                statusRow(title: "Migration status", value: appState.migrationStatus)
                statusRow(title: "FX refresh", value: appState.fxRefreshStatusText)
                statusRow(title: "Recurring generation", value: appState.recurringGenerationStatusText)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Database path")
                    .font(.headline)

                Text(appState.databaseManager.databasePath)
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Table counts")
                    .font(.headline)

                statusRow(title: "Currencies", value: "\(appState.currencyCount)")
                statusRow(title: "Accounts", value: "\(appState.accountCount)")
                statusRow(title: "Transactions", value: "\(appState.transactionCount)")
                statusRow(title: "Entries", value: "\(appState.entryCount)")
                statusRow(title: "Partners", value: "\(appState.partnerCount)")
            }

            if let lastErrorMessage = appState.lastErrorMessage {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Last error")
                        .font(.headline)
                    Text(lastErrorMessage)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            }

            if !appState.operationalIssues.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Operational issues")
                        .font(.headline)

                    ForEach(appState.operationalIssues) { issue in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(issue.kind.title)
                                .fontWeight(.medium)
                            Text(issue.message)
                                .foregroundStyle(.red)
                                .textSelection(.enabled)
                        }
                    }
                }
            }

            HStack {
                Button("Refresh FX Rates Now") {
                    Task {
                        await appState.refreshFxRatesManually()
                    }
                }

                Button("Reveal in Finder") {
                    appState.revealDatabaseInFinder()
                }

                Button("Refresh") {
                    appState.refreshDashboard()
                }
            }
        }
        .padding(24)
        .frame(minWidth: 560, minHeight: 420, alignment: .topLeading)
    }

    private func statusRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
    }
}
