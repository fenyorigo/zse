import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ExportTransactionsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState

    let selectedAccount: Account?

    @State private var scope: ExportScope = .full
    @State private var options = ZseFlatFileOptions()
    @State private var operationMessage: String?
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Export Transactions")
                .font(.title3)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 10) {
                pickerRow("Scope", selection: $scope, values: ExportScope.allCases)

                if scope == .selectedAccount {
                    detailRow("Selected Account", selectedAccount?.name ?? "No account selected")
                }

                Divider()

                pickerRow("Extension", selection: $options.fileExtension, values: FlatFileExtensionOption.allCases)
                pickerRow("Delimiter", selection: $options.delimiter, values: FlatFileDelimiterOption.allCases)
                pickerRow("Date Format", selection: $options.dateFormat, values: FlatFileDateFormatOption.allCases)
                pickerRow("Decimal Separator", selection: $options.decimalSeparator, values: FlatFileDecimalSeparatorOption.allCases)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("zse Flat Export")
                    .font(.headline)
                Text("One row per transaction, UTF-8, with full account and category paths for round-trip import.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let operationMessage {
                Text(operationMessage)
                    .font(.footnote)
                    .foregroundStyle(.green)
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

                Button("Export...") {
                    exportTransactions()
                }
                .disabled(scope == .selectedAccount && selectedAccount?.id == nil)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 560)
    }

    private func exportTransactions() {
        let panel = NSSavePanel()
        panel.title = "Export Transactions"
        panel.nameFieldStringValue = appState.zseFlatFileService.defaultExportURL(
            scope: scope,
            selectedAccount: selectedAccount,
            options: options
        ).lastPathComponent
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [
            UTType(filenameExtension: options.fileExtension.rawValue) ?? .plainText
        ]

        guard panel.runModal() == .OK, let destinationURL = panel.url else {
            return
        }

        do {
            let summary = try appState.zseFlatFileService.exportTransactions(
                scope: scope,
                selectedAccountID: selectedAccount?.id,
                destinationURL: destinationURL,
                options: options
            )
            operationMessage = "Exported \(summary.exportedTransactionCount) transactions to \(summary.destinationURL.lastPathComponent)."
            errorMessage = nil
        } catch {
            operationMessage = nil
            errorMessage = error.localizedDescription
        }
    }

    private func pickerRow<Value: CaseIterable & Identifiable & Hashable>(
        _ title: String,
        selection: Binding<Value>,
        values: Value.AllCases
    ) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 140, alignment: .leading)

            Picker(title, selection: selection) {
                ForEach(Array(values)) { value in
                    Text(displayText(for: value)).tag(value)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.footnote)
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 140, alignment: .leading)
            Text(value)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.footnote)
    }

    private func displayText<Value>(for value: Value) -> String {
        switch value {
        case let scope as ExportScope:
            return scope.title
        case let fileExtension as FlatFileExtensionOption:
            return fileExtension.title
        case let delimiter as FlatFileDelimiterOption:
            return delimiter.title
        case let dateFormat as FlatFileDateFormatOption:
            return dateFormat.title
        case let decimalSeparator as FlatFileDecimalSeparatorOption:
            return decimalSeparator.title
        default:
            return ""
        }
    }
}
