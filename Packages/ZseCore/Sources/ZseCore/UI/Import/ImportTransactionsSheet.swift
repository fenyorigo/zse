import SwiftUI

struct ImportTransactionsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: ImportViewModel
    @State private var hasCompletedImport = false
    @State private var selectedFormat: ManualImportFormat = .moneydance
    @State private var zseOptions = ZseFlatFileOptions()
    let onImported: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Import Transactions")
                .font(.title3)
                .fontWeight(.semibold)

            HStack {
                Text("Import Format")
                    .foregroundStyle(.secondary)
                    .frame(width: 120, alignment: .leading)

                Picker("Import Format", selection: $selectedFormat) {
                    ForEach(ManualImportFormat.allCases) { format in
                        Text(format.title).tag(format)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)

                Spacer()
            }
            .font(.footnote)

            if selectedFormat == .zse {
                zseOptionsSection
            }

            HStack(spacing: 8) {
                Button("Select File...") {
                    viewModel.chooseFile(format: selectedFormat, zseOptions: zseOptions)
                }
                .controlSize(.small)

                if let selectedFileURL = viewModel.selectedFileURL {
                    Text(selectedFileURL.lastPathComponent)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            if let previewSummary = viewModel.previewSummary {
                previewSection(previewSummary)
            } else {
                ContentUnavailableView(
                    "Choose an export file",
                    systemImage: "square.and.arrow.down",
                    description: Text(selectedFormat == .moneydance ? "Import v1 fully supports Moneydance-style tab-delimited account exports." : "zse flat import expects a header row and uses the explicit parser options above.")
                )
                .frame(maxWidth: .infinity, minHeight: 220)
            }

            if let preview = viewModel.preview, !preview.warnings.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Warnings")
                        .font(.headline)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(preview.warnings.prefix(20)) { warning in
                                Text(warningLine(warning))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .frame(maxHeight: 140)
                }
            }

            if let resultSummary = viewModel.resultSummary {
                resultSection(resultSummary)
            }

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()

                Button("Close") {
                    closeSheet()
                }
                .keyboardShortcut(.cancelAction)

                if hasCompletedImport {
                    Button("Done") {
                        closeSheet()
                    }
                    .keyboardShortcut(.defaultAction)
                } else {
                    Button("Import") {
                        commitImport()
                    }
                    .disabled(viewModel.previewSummary == nil || viewModel.isImporting)
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(16)
        .frame(width: 620)
        .onChange(of: viewModel.selectedFileURL) { _, _ in
            hasCompletedImport = false
        }
        .onChange(of: selectedFormat) { _, _ in
            hasCompletedImport = false
            viewModel.loadPreview(format: selectedFormat, zseOptions: zseOptions)
        }
        .onChange(of: zseOptions) { _, _ in
            hasCompletedImport = false
            if selectedFormat == .zse {
                viewModel.loadPreview(format: selectedFormat, zseOptions: zseOptions)
            }
        }
    }

    private var zseOptionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            optionPickerRow("Delimiter", selection: $zseOptions.delimiter, values: FlatFileDelimiterOption.allCases)
            optionPickerRow("Date Format", selection: $zseOptions.dateFormat, values: FlatFileDateFormatOption.allCases)
            optionPickerRow("Decimal Separator", selection: $zseOptions.decimalSeparator, values: FlatFileDecimalSeparatorOption.allCases)
        }
    }

    private func previewSection(_ summary: ImportPreviewSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Preview")
                .font(.headline)

            detailRow("Format", summary.formatDescription)
            detailRow("Source Account", summary.sourceAccountPath ?? "")
            detailRow("Source Currency", summary.sourceAccountCurrency ?? "")
            detailRow("Parsed Transactions", "\(summary.parsedTransactionCount)")
            detailRow("Continuation Rows", "\(summary.continuationRowCount)")
            detailRow("Accounts To Create", "\(summary.accountsToCreateCount)")
            detailRow("Categories To Create", "\(summary.categoriesToCreateCount)")
            detailRow("Source Categories", "\(summary.sourceCategoryPathCount)")
            detailRow("Missing Categories", "\(summary.missingCategoryPathsCount)")
            detailRow("Income", "\(summary.incomeCount)")
            detailRow("Expenses", "\(summary.expenseCount)")
            detailRow("Same-Currency Transfers", "\(summary.sameCurrencyTransferCount)")
            detailRow("Cross-Currency Transfers", "\(summary.crossCurrencyTransferCount)")
            detailRow("Fallback Classifications", "\(summary.fallbackClassificationCount)")
            detailRow("Warnings", "\(summary.warningsCount)")
            detailRow("Skipped Rows", "\(summary.skippedRowCount)")
        }
    }

    private func resultSection(_ result: ImportCommitResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Import Result")
                .font(.headline)

            detailRow("Imported Transactions", "\(result.importedTransactionCount)")
            detailRow("Created Accounts", "\(result.createdAccountsCount)")
            detailRow("Created Categories", "\(result.createdCategoriesCount)")
            detailRow("Source Categories", "\(result.sourceCategoryPathCount)")
            detailRow("Missing Categories After Import", "\(result.missingCategoryPathsAfterImportCount)")
            detailRow("Created Bank Accounts", "\(result.createdBankAccountsCount)")
            detailRow("Created Cash Accounts", "\(result.createdCashAccountsCount)")
            detailRow("Created Investment Accounts", "\(result.createdInvestmentAccountsCount)")
            detailRow("Created Liability Accounts", "\(result.createdLiabilityAccountsCount)")
            detailRow("Created Credit Cards", "\(result.createdCreditCardAccountsCount)")
            detailRow("Income", "\(result.incomeCount)")
            detailRow("Expenses", "\(result.expenseCount)")
            detailRow("Same-Currency Transfers", "\(result.sameCurrencyTransferCount)")
            detailRow("Cross-Currency Transfers", "\(result.crossCurrencyTransferCount)")
            detailRow("Fallback Classifications", "\(result.fallbackClassificationCount)")
            detailRow("Warnings", "\(result.warningsCount)")
            detailRow("Skipped Rows", "\(result.skippedRowCount)")
        }
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 180, alignment: .leading)
            Text(value.isEmpty ? " " : value)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.footnote)
    }

    private func warningLine(_ warning: ImportWarning) -> String {
        if let lineNumber = warning.lineNumber {
            return "Line \(lineNumber): \(warning.message)"
        }
        return warning.message
    }

    private func optionPickerRow<Value: CaseIterable & Identifiable & Hashable>(
        _ title: String,
        selection: Binding<Value>,
        values: Value.AllCases
    ) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 120, alignment: .leading)

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

    private func displayText<Value>(for value: Value) -> String {
        switch value {
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

    private func commitImport() {
        do {
            _ = try viewModel.commitImport()
            hasCompletedImport = true
        } catch {
        }
    }

    private func closeSheet() {
        if hasCompletedImport {
            onImported()
        }
        dismiss()
    }
}
