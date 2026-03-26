import SwiftUI

struct DatabaseMaintenanceSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState

    @State private var pendingRestoreURL: URL?
    @State private var pendingWipeScope: DatabaseWipeScope?
    @State private var operationMessage: String?
    @State private var errorMessage: String?

    let onDatabaseChanged: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Database Maintenance")
                .font(.title3)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 10) {
                Text("Backup and Restore")
                    .font(.headline)

                HStack(spacing: 8) {
                    Button("Back Up Database...") {
                        backupDatabase()
                    }

                    Button("Restore Database...") {
                        chooseRestoreFile()
                    }

                    Button("Reveal Database") {
                        appState.revealDatabaseInFinder()
                    }

                    Button("Reveal Backup Folder") {
                        appState.revealBackupFolderInFinder()
                    }
                }
                .controlSize(.small)
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text("Wipe Data")
                    .font(.headline)

                ForEach(DatabaseWipeScope.allCases) { scope in
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(scope.title)
                                .fontWeight(.medium)
                            Text(scope.explanation)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button(scope.title, role: .destructive) {
                            pendingWipeScope = scope
                        }
                        .controlSize(.small)
                    }
                }
            }

            if let operationMessage {
                Text(operationMessage)
                    .font(.footnote)
                    .foregroundStyle(.primary)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(16)
        .frame(width: 620)
        .confirmationDialog(
            "Restore Database?",
            isPresented: Binding(
                get: { pendingRestoreURL != nil },
                set: { newValue in
                    if !newValue {
                        pendingRestoreURL = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            Button("Restore Database", role: .destructive) {
                restoreDatabase()
            }
        } message: {
            Text("The current database will be replaced. A safety backup of the current database will be created first.")
        }
        .confirmationDialog(
            pendingWipeScope?.title ?? "Confirm Wipe",
            isPresented: Binding(
                get: { pendingWipeScope != nil },
                set: { newValue in
                    if !newValue {
                        pendingWipeScope = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            Button(pendingWipeScope?.title ?? "Wipe", role: .destructive) {
                wipeDatabase()
            }
        } message: {
            Text(pendingWipeScope?.explanation ?? "")
        }
    }

    private func backupDatabase() {
        do {
            guard let backupURL = try appState.backupDatabaseInteractively() else {
                return
            }
            operationMessage = "Backup created: \(backupURL.lastPathComponent)"
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func chooseRestoreFile() {
        pendingRestoreURL = appState.pickRestoreBackupURL()
    }

    private func restoreDatabase() {
        guard let pendingRestoreURL else {
            return
        }

        do {
            let safetyBackupURL = try appState.restoreDatabase(from: pendingRestoreURL)
            operationMessage = "Database restored. Safety backup created: \(safetyBackupURL.lastPathComponent)"
            errorMessage = nil
            self.pendingRestoreURL = nil
            onDatabaseChanged()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func wipeDatabase() {
        guard let pendingWipeScope else {
            return
        }

        do {
            try appState.wipeDatabase(scope: pendingWipeScope)
            operationMessage = "\(pendingWipeScope.title) completed."
            errorMessage = nil
            self.pendingWipeScope = nil
            onDatabaseChanged()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
