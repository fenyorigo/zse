import SwiftUI

struct AccountSidebarView: View {
    @ObservedObject var viewModel: AccountSidebarViewModel
    @Binding var selection: SidebarSelection?

    var body: some View {
        List(selection: $selection) {
            ForEach(viewModel.sections) { sectionModel in
                Section {
                    if sectionModel.nodes.isEmpty {
                        Text("No accounts")
                            .font(.footnote)
                            .foregroundStyle(.tertiary)
                    } else {
                        ForEach(sectionModel.nodes) { node in
                            SidebarNodeRow(viewModel: viewModel, node: node, selection: $selection)
                        }
                    }
                } header: {
                    Text(sectionModel.section.title)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.sidebar)
    }
}

private struct SidebarNodeRow: View {
    @ObservedObject var viewModel: AccountSidebarViewModel
    let node: SidebarNode
    @Binding var selection: SidebarSelection?
    @State private var isExpanded = true

    var body: some View {
        if node.children.isEmpty {
            selectableLabel
        } else {
            DisclosureGroup(isExpanded: $isExpanded) {
                ForEach(node.children) { childNode in
                    SidebarNodeRow(viewModel: viewModel, node: childNode, selection: $selection)
                }
            } label: {
                selectableLabel
            }
        }
    }

    private var selectableLabel: some View {
        label(for: node)
            .contentShape(Rectangle())
            .tag(node.selection)
            .onTapGesture {
                if let nodeSelection = node.selection {
                    selection = nodeSelection
                }
            }
            .contextMenu {
                if case let .account(account) = node.kind,
                   let accountID = account.id {
                    Button(account.isHidden ? "Unhide" : "Hide") {
                        viewModel.setHidden(!account.isHidden, accountID: accountID)
                        if !viewModel.showHiddenAccounts,
                           selection == node.selection,
                           !account.isHidden {
                            selection = nil
                        }
                    }
                }
            }
    }

    @ViewBuilder
    private func label(for node: SidebarNode) -> some View {
        let isSelected = selection == node.selection

        HStack {
            switch node.kind {
            case .grouping:
                Label(node.title, systemImage: "folder")
            case .currency:
                Label(node.title, systemImage: "coloncurrencysign.circle")
            case .account(let account):
                Label(node.title, systemImage: account.isGroup ? "folder" : "building.columns")
            }

            Spacer(minLength: 12)

            if let formattedBalance = node.formattedBalance {
                Text(formattedBalance)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(isSelected ? .white : .secondary)
            }
        }
        .foregroundStyle(isSelected ? .white : .primary)
        .fontWeight(isSelected ? .semibold : .regular)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(
                    isSelected
                        ? Color(
                            red: 43.0 / 255.0,
                            green: 81.0 / 255.0,
                            blue: 85.0 / 255.0
                        )
                        : Color.clear
                )
        )
    }
}
