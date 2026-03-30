import SwiftUI

struct EditTransactionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: EditTransactionViewModel
    @State private var isShowingDeleteConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Edit Transaction")
                .font(.title3)
                .fontWeight(.semibold)

            Form {
                DatePicker("Date", selection: $viewModel.date, displayedComponents: .date)
                TextField("Description", text: $viewModel.descriptionText)
                Picker("Type", selection: $viewModel.transactionType) {
                    ForEach(viewModel.typeOptions) { type in
                        Text(type.rawValue.capitalized).tag(type)
                    }
                }
                .onChange(of: viewModel.transactionType) { _, _ in
                    viewModel.transactionTypeDidChange()
                }
                Picker("State", selection: $viewModel.state) {
                    Text("Uncleared").tag("uncleared")
                    Text("Pending").tag("reconciling")
                    Text("Cleared").tag("cleared")
                }

                if viewModel.isCounterpartEditable {
                    SearchableSelectionField(
                        title: viewModel.counterpartLabel,
                        placeholder: "Type to filter options",
                        selectedID: $viewModel.selectedCounterpartAccountID,
                        options: viewModel.counterpartOptions,
                        displayText: { $0.displayName }
                    )
                    .onChange(of: viewModel.selectedCounterpartAccountID) { _, _ in
                        viewModel.counterpartDidChange()
                    }
                } else {
                    LabeledContent(viewModel.counterpartLabel) {
                        Text("Simple transaction type reassignment is not available for this transaction.")
                            .foregroundStyle(.secondary)
                    }
                }

                if viewModel.isCounterpartEditable {
                    HStack {
                        TextField(
                            viewModel.transactionType == .transfer ? viewModel.currentAccountName : "Amount",
                            text: $viewModel.currentAmountText
                        )
                        Text(viewModel.currentCurrency)
                            .foregroundStyle(.secondary)
                    }

                    if viewModel.transactionType == .transfer, viewModel.isCrossCurrencyTransfer {
                        HStack {
                            TextField("Transfer Account Amount", text: $viewModel.counterpartAmountText)
                            Text(viewModel.counterpartCurrency ?? "")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .controlSize(.small)

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.footnote)
            }

            HStack {
                Button("Delete Transaction", role: .destructive) {
                    isShowingDeleteConfirmation = true
                }
                .disabled(!viewModel.canDelete)

                if !viewModel.canDelete {
                    Text("Only uncleared transactions can be deleted.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Cancel") {
                    dismiss()
                }

                Button("Save") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(viewModel.isSaving)
            }
        }
        .padding(16)
        .frame(width: 460)
        .confirmationDialog(
            "Delete Transaction?",
            isPresented: $isShowingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Transaction", role: .destructive) {
                deleteTransaction()
            }
        } message: {
            Text("Deleting a transfer deletes the whole transaction from both sides.")
        }
    }

    private func save() {
        do {
            try viewModel.save()
            dismiss()
        } catch {
        }
    }

    private func deleteTransaction() {
        do {
            try viewModel.deleteTransaction()
            dismiss()
        } catch {
        }
    }
}
