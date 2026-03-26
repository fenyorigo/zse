import SwiftUI

struct RecurringRuleEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: RecurringRuleEditorViewModel
    let onSaved: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Recurring Transaction")
                .font(.title3)
                .fontWeight(.semibold)

            Form {
                TextField("Name", text: $viewModel.name)

                Picker("Transaction Type", selection: $viewModel.transactionType) {
                    ForEach(RecurringTransactionType.allCases) { type in
                        Text(type.title).tag(type)
                    }
                }
                .onChange(of: viewModel.transactionType) { _, _ in
                    viewModel.transactionTypeDidChange()
                }

                typeSpecificFields

                HStack {
                    TextField("Amount", text: $viewModel.amountText)
                    Text(viewModel.selectedCurrencyCode ?? "")
                        .foregroundStyle(.secondary)
                }

                TextField("Description", text: $viewModel.descriptionText)
                TextField("Memo", text: $viewModel.memoText)

                Picker("Default Status", selection: $viewModel.defaultState) {
                    Text("Uncleared").tag("uncleared")
                    Text("Reconciling").tag("reconciling")
                    Text("Cleared").tag("cleared")
                }

                Picker("Recurrence", selection: $viewModel.recurrenceType) {
                    ForEach(RecurrenceType.allCases) { type in
                        Text(type.title).tag(type)
                    }
                }

                TextField("Interval", text: $viewModel.intervalText)

                if viewModel.recurrenceType == .monthlyFixedDay {
                    TextField("Day of Month", text: $viewModel.dayOfMonthText)
                }

                DatePicker("Start Date", selection: $viewModel.startDate, displayedComponents: .date)

                Picker("End Condition", selection: $viewModel.endMode) {
                    ForEach(RecurringEndMode.allCases) { endMode in
                        Text(endMode.title).tag(endMode)
                    }
                }

                if viewModel.endMode == .count {
                    TextField("Max Occurrences", text: $viewModel.maxOccurrencesText)
                }

                if viewModel.endMode == .date {
                    DatePicker("End Date", selection: $viewModel.endDate, displayedComponents: .date)
                }

                Toggle("Active", isOn: $viewModel.isActive)
            }
            .formStyle(.grouped)
            .controlSize(.small)

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
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
                .disabled(viewModel.isSaving)
            }
        }
        .padding(16)
        .frame(width: 520)
        .task {
            viewModel.loadFormData()
        }
    }

    @ViewBuilder
    private var typeSpecificFields: some View {
        switch viewModel.transactionType {
        case .income:
            Picker("Target Account", selection: $viewModel.selectedTargetAccountID) {
                ForEach(viewModel.targetAccountOptions) { option in
                    Text(option.displayName).tag(Optional(option.id))
                }
            }

            Picker("Income Category", selection: $viewModel.selectedCategoryAccountID) {
                ForEach(viewModel.categoryOptions) { option in
                    Text(option.displayName).tag(Optional(option.id))
                }
            }
        case .expense:
            Picker("Source Account", selection: $viewModel.selectedSourceAccountID) {
                ForEach(viewModel.sourceAccountOptions) { option in
                    Text(option.displayName).tag(Optional(option.id))
                }
            }

            Picker("Expense Category", selection: $viewModel.selectedCategoryAccountID) {
                ForEach(viewModel.categoryOptions) { option in
                    Text(option.displayName).tag(Optional(option.id))
                }
            }
        case .transfer:
            Picker("Source Account", selection: $viewModel.selectedSourceAccountID) {
                ForEach(viewModel.sourceAccountOptions) { option in
                    Text(option.displayName).tag(Optional(option.id))
                }
            }

            Picker("Target Account", selection: $viewModel.selectedTargetAccountID) {
                ForEach(viewModel.targetAccountOptions) { option in
                    Text(option.displayName).tag(Optional(option.id))
                }
            }
        }
    }

    private func save() {
        do {
            try viewModel.save()
            onSaved()
            dismiss()
        } catch {
        }
    }
}
