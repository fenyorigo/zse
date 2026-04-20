import SwiftUI

struct HiddenAccountManagerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: AccountSidebarViewModel

    @State private var accountNodes: [AccountSidebarViewModel.HiddenAccountNode] = []
    @State private var visibleLeafAccountIDs = Set<Int64>()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Manage Hidden Accounts")
                .font(.title3)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 10) {
                Text("Visibility")
                    .font(.headline)

                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(accountNodes) { node in
                            HiddenAccountNodeView(
                                node: node,
                                visibleLeafAccountIDs: $visibleLeafAccountIDs
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }
                .frame(height: 320)
                .padding(8)
                .background(.quaternary.opacity(0.18), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            Text("Checked accounts remain visible persistently. Checking a parent makes its full subtree visible; unchecking it hides the full subtree.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()

                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Apply") {
                    viewModel.applyVisibleLeafAccountIDs(visibleLeafAccountIDs)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 620)
        .onAppear {
            loadVisibility()
        }
    }

    private func loadVisibility() {
        accountNodes = viewModel.hiddenAccountNodes()
        visibleLeafAccountIDs = viewModel.visibleLeafAccountIDs()
    }
}

private struct HiddenAccountNodeView: View {
    private static let chevronSlotWidth: CGFloat = 14

    let node: AccountSidebarViewModel.HiddenAccountNode
    @Binding var visibleLeafAccountIDs: Set<Int64>

    var body: some View {
        if node.children.isEmpty {
            HStack(spacing: 0) {
                Image(systemName: "chevron.right")
                    .opacity(0)
                    .frame(width: Self.chevronSlotWidth)

                Toggle(isOn: leafVisibilityBinding) {
                    Text(node.account.name)
                }
                .toggleStyle(.checkbox)
            }
        } else {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(node.children) { child in
                        HiddenAccountNodeView(node: child, visibleLeafAccountIDs: $visibleLeafAccountIDs)
                    }
                }
                .padding(.leading, 18)
                .padding(.top, 4)
            } label: {
                Toggle(isOn: groupVisibilityBinding) {
                    Text(node.account.name)
                }
                .toggleStyle(.checkbox)
            }
        }
    }

    private var leafVisibilityBinding: Binding<Bool> {
        Binding(
            get: {
                guard let accountID = node.account.id else {
                    return false
                }
                return visibleLeafAccountIDs.contains(accountID)
            },
            set: { isVisible in
                guard let accountID = node.account.id else {
                    return
                }
                if isVisible {
                    visibleLeafAccountIDs.insert(accountID)
                } else {
                    visibleLeafAccountIDs.remove(accountID)
                }
            }
        )
    }

    private var groupVisibilityBinding: Binding<Bool> {
        Binding(
            get: {
                !node.descendantLeafIDs.isEmpty && !node.descendantLeafIDs.isDisjoint(with: visibleLeafAccountIDs)
            },
            set: { isVisible in
                if isVisible {
                    visibleLeafAccountIDs.formUnion(node.descendantLeafIDs)
                } else {
                    visibleLeafAccountIDs.subtract(node.descendantLeafIDs)
                }
            }
        )
    }
}
