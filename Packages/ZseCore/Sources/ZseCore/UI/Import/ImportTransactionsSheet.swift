import SwiftUI

struct ImportTransactionsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: ImportViewModel
    let onImported: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Import Transactions")
                .font(.title3)
                .fontWeight(.semibold)

            HStack(spacing: 8) {
                Button("Select File...") {
                    viewModel.chooseFile()
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
                    description: Text("Import v1 fully supports Moneydance-style tab-delimited account exports.")
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
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Import") {
                    commitImport()
                }
                .disabled(viewModel.previewSummary == nil || viewModel.isImporting)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 620)
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
            detailRow("Income", "\(summary.incomeCount)")
            detailRow("Expenses", "\(summary.expenseCount)")
            detailRow("Same-Currency Transfers", "\(summary.sameCurrencyTransferCount)")
            detailRow("Cross-Currency Transfers", "\(summary.crossCurrencyTransferCount)")
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
            detailRow("Created Bank Accounts", "\(result.createdBankAccountsCount)")
            detailRow("Created Cash Accounts", "\(result.createdCashAccountsCount)")
            detailRow("Created Investment Accounts", "\(result.createdInvestmentAccountsCount)")
            detailRow("Created Liability Accounts", "\(result.createdLiabilityAccountsCount)")
            detailRow("Created Credit Cards", "\(result.createdCreditCardAccountsCount)")
            detailRow("Income", "\(result.incomeCount)")
            detailRow("Expenses", "\(result.expenseCount)")
            detailRow("Same-Currency Transfers", "\(result.sameCurrencyTransferCount)")
            detailRow("Cross-Currency Transfers", "\(result.crossCurrencyTransferCount)")
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

    private func commitImport() {
        do {
            _ = try viewModel.commitImport()
            onImported()
        } catch {
        }
    }
}
