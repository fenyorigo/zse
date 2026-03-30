import SwiftUI

struct SearchableSelectionField<Option: Identifiable & Hashable>: View where Option.ID: Hashable {
    let title: String
    let placeholder: String
    @Binding var selectedID: Option.ID?
    let options: [Option]
    let displayText: (Option) -> String

    @State private var query = ""
    @State private var isExpanded = false
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField(placeholder, text: $query)
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)
                .onTapGesture {
                    isExpanded = true
                }
                .onChange(of: query) { _, _ in
                    if isFocused {
                        isExpanded = true
                    }
                }
                .onChange(of: selectedID) { _, _ in
                    synchronizeQueryWithSelection()
                }
                .onAppear {
                    synchronizeQueryWithSelection()
                }

            if isExpanded {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        if filteredOptions.isEmpty {
                            Text("No matches")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            ForEach(filteredOptions) { option in
                                Button {
                                    selectedID = option.id
                                    query = displayText(option)
                                    isExpanded = false
                                    isFocused = false
                                } label: {
                                    Text(displayText(option))
                                        .lineLimit(2)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 6)
                                }
                                .buttonStyle(.plain)
                                .background(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(selectedID == option.id ? Color.accentColor.opacity(0.12) : Color.clear)
                                )
                            }
                        }
                    }
                }
                .frame(maxHeight: 140)
                .padding(4)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }

    private var filteredOptions: [Option] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return options
        }

        return options.filter { option in
            displayText(option).localizedCaseInsensitiveContains(trimmedQuery)
        }
    }

    private func synchronizeQueryWithSelection() {
        guard let selectedID,
              let selectedOption = options.first(where: { $0.id == selectedID }) else {
            if !isFocused {
                query = ""
            }
            return
        }

        if !isFocused {
            query = displayText(selectedOption)
        }
    }
}
