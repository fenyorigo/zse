import SwiftUI

struct EditAccountSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: EditAccountViewModel
    let onSaved: (Int64) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Edit Account")
                .font(.title2)
                .fontWeight(.semibold)

            Form {
                TextField("Name", text: $viewModel.name)

                Picker("Parent Account", selection: $viewModel.selectedParentAccountID) {
                    Text("None").tag(Optional<Int64>.none)
                    ForEach(viewModel.availableParents) { account in
                        Text(account.name).tag(Optional(account.id))
                    }
                }
                .onChange(of: viewModel.selectedParentAccountID) { _, _ in
                    viewModel.synchronizeCurrencyWithParent()
                }

                Picker("Class", selection: $viewModel.accountClass) {
                    ForEach(viewModel.accountClasses, id: \.self) { accountClass in
                        Text(accountClass.capitalized).tag(accountClass)
                    }
                }

                Picker("Subtype", selection: $viewModel.subtype) {
                    ForEach(viewModel.accountSubtypes, id: \.self) { subtype in
                        Text(subtype.capitalized).tag(subtype)
                    }
                }

                Picker("Currency", selection: $viewModel.currencyCode) {
                    ForEach(viewModel.availableCurrencies) { currency in
                        Text("\(currency.code) • \(currency.name)").tag(currency.code)
                    }
                }

                if viewModel.canEditAccumulationCurrency {
                    Picker("Accumulate Balance In", selection: $viewModel.accumulationCurrencyCode) {
                        Text("Use Account Currency").tag(Optional<String>.none)
                        ForEach(viewModel.accumulationCurrencyOptions) { currency in
                            Text("\(currency.code) • \(currency.name)").tag(Optional(currency.code))
                        }
                    }
                }

                if viewModel.isCreditLimitEditable {
                    TextField("Credit Limit (HUF)", text: $viewModel.creditLimitText)
                    TextField("Remaining Warning Threshold (%)", text: $viewModel.creditAvailabilityWarningPercentText)
                }

                Toggle("Is Group", isOn: $viewModel.isGroup)
                Toggle("Hide", isOn: $viewModel.isHidden)
                Toggle("Include in Net Worth", isOn: $viewModel.includeInNetWorth)
                TextField("Opening Balance", text: $viewModel.openingBalanceText)
                Toggle("Set Opening Balance Date", isOn: $viewModel.hasOpeningBalanceDate)

                if viewModel.hasOpeningBalanceDate {
                    DatePicker(
                        "Opening Balance Date",
                        selection: $viewModel.openingBalanceDate,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.field)
                }

                TextField("Sort Order", text: $viewModel.sortOrderText)

                if let parentAccount = viewModel.selectedParentAccount {
                    LabeledContent("Parent Details") {
                        Text(parentAccount.subtitle)
                            .foregroundStyle(.secondary)
                    }
                }
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
                .disabled(viewModel.isSaving)
            }
        }
        .padding(20)
        .frame(width: 460)
        .task {
            viewModel.loadFormData()
        }
    }

    private func save() {
        do {
            let accountID = try viewModel.save()
            onSaved(accountID)
            dismiss()
        } catch {
        }
    }
}
