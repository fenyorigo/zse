import SwiftUI

struct NewTransactionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: NewTransactionViewModel
    let onSaved: (Int64) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("New Transaction")
                .font(.title2)
                .fontWeight(.semibold)

            Form {
                Picker("Type", selection: $viewModel.transactionType) {
                    ForEach(NewTransactionType.allCases) { transactionType in
                        Text(transactionType.title).tag(transactionType)
                    }
                }
                .onChange(of: viewModel.transactionType) { _, _ in
                    viewModel.transactionTypeDidChange()
                }

                DatePicker("Date", selection: $viewModel.date, displayedComponents: .date)

                TextField("Description", text: $viewModel.descriptionText)

                Picker("State", selection: $viewModel.state) {
                    Text("Uncleared").tag("uncleared")
                    Text("Reconciling").tag("reconciling")
                    Text("Cleared").tag("cleared")
                }

                typeSpecificFields

                TextField("Partner", text: $viewModel.partnerName)
                if viewModel.transactionType != .transfer {
                    TextField("Amount", text: $viewModel.amountText)
                }
                TextField("Memo", text: $viewModel.memo)
            }
            .formStyle(.grouped)

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.footnote)
            }

            HStack {
                Spacer()

                Button("Cancel") {
                    dismiss()
                }

                Button("Save") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!viewModel.canSave)
            }
        }
        .padding(20)
        .frame(width: 520)
        .task {
            viewModel.loadFormData()
        }
    }

    @ViewBuilder
    private var typeSpecificFields: some View {
        switch viewModel.transactionType {
        case .deposit:
            LabeledContent("Current Account") {
                Text(viewModel.currentAccountDisplayName)
            }

            Picker(viewModel.categoryLabel, selection: $viewModel.selectedCategoryAccountID) {
                ForEach(viewModel.selectedCategoryOptions) { option in
                    Text(option.displayName).tag(Optional(option.id))
                }
            }

            if viewModel.selectedCategoryOptions.isEmpty {
                Text("No income categories are available. Create an income leaf account first.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        case .spending:
            LabeledContent("Current Account") {
                Text(viewModel.currentAccountDisplayName)
            }

            Picker(viewModel.categoryLabel, selection: $viewModel.selectedCategoryAccountID) {
                ForEach(viewModel.selectedCategoryOptions) { option in
                    Text(option.displayName).tag(Optional(option.id))
                }
            }

            if viewModel.selectedCategoryOptions.isEmpty {
                Text("No expense categories are available. Create an expense leaf account first.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        case .transfer:
            Picker("From Account", selection: $viewModel.selectedFromAccountID) {
                ForEach(viewModel.fromAccountOptions) { option in
                    Text(option.displayName).tag(Optional(option.id))
                }
            }
            .onChange(of: viewModel.selectedFromAccountID) { _, _ in
                viewModel.transactionTypeDidChange()
            }

            Picker("To Account", selection: $viewModel.selectedToAccountID) {
                ForEach(viewModel.toAccountOptions) { option in
                    Text(option.displayName).tag(Optional(option.id))
                }
            }
            .onChange(of: viewModel.selectedToAccountID) { _, _ in
                viewModel.transactionTypeDidChange()
            }

            if viewModel.toAccountOptions.isEmpty {
                Text("No transfer accounts are available.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if viewModel.isCrossCurrencyTransfer {
                HStack {
                    TextField("Source Amount", text: $viewModel.sourceAmountText)
                    Text(viewModel.transferSourceCurrency)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    TextField("Target Amount", text: $viewModel.targetAmountText)
                    Text(viewModel.transferTargetCurrency)
                        .foregroundStyle(.secondary)
                }

                if let effectiveRateText = viewModel.effectiveRateText {
                    LabeledContent("Derived Rate") {
                        Text(effectiveRateText)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                HStack {
                    TextField("Amount", text: $viewModel.amountText)
                    Text(viewModel.transferSourceCurrency)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func save() {
        do {
            let transactionID = try viewModel.save()
            onSaved(transactionID)
            dismiss()
        } catch {
        }
    }
}
