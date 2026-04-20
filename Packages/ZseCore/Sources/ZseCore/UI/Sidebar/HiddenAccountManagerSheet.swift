import SwiftUI

struct HiddenAccountManagerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: AccountSidebarViewModel

    @State private var selectedAccountID: Int64?

    private var options: [AccountSidebarViewModel.HiddenAccountOption] {
        viewModel.hiddenAccountOptions()
    }

    private var selectedOption: AccountSidebarViewModel.HiddenAccountOption? {
        guard let selectedAccountID else {
            return nil
        }
        return options.first(where: { $0.id == selectedAccountID })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Manage Hidden Accounts")
                .font(.title3)
                .fontWeight(.semibold)

            SearchableSelectionField(
                title: "Account",
                placeholder: "Type to filter accounts",
                selectedID: $selectedAccountID,
                options: options,
                displayText: { option in
                    option.fullPath + (option.isHidden ? " • hidden" : "")
                }
            )

            HStack {
                Text("Status")
                    .foregroundStyle(.secondary)
                    .frame(width: 80, alignment: .leading)

                Text(selectedOption?.isHidden == true ? "Hidden" : "Visible")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.footnote)

            HStack {
                Spacer()

                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Hide") {
                    guard let selectedOption else { return }
                    viewModel.setHidden(true, accountID: selectedOption.id)
                }
                .disabled(selectedOption == nil || selectedOption?.isHidden == true)

                Button("Unhide") {
                    guard let selectedOption else { return }
                    viewModel.setHidden(false, accountID: selectedOption.id)
                }
                .disabled(selectedOption == nil || selectedOption?.isHidden == false)
            }
        }
        .padding(16)
        .frame(width: 520)
    }
}
