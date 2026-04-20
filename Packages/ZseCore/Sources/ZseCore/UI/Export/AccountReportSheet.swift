import AppKit
import SwiftUI

fileprivate struct AccountReportNode: Identifiable {
    let account: Account
    let children: [AccountReportNode]

    var id: Int64 { account.id ?? 0 }
}

struct AccountReportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState

    @State private var accountNodes: [AccountReportNode] = []
    @State private var selectedLeafAccountIDs = Set<Int64>()
    @State private var afterDateText = "1900-01-01"
    @State private var beforeDateText = "2100-12-31"
    @State private var operationMessage: String?
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Account Report")
                .font(.title3)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 10) {
                Text("Accounts")
                    .font(.headline)

                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(accountNodes) { node in
                            AccountReportNodeView(
                                node: node,
                                selectedLeafAccountIDs: $selectedLeafAccountIDs
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }
                .frame(height: 260)
                .padding(8)
                .background(.quaternary.opacity(0.18), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Date Range")
                    .font(.headline)

                HStack {
                    Text("After date")
                        .foregroundStyle(.secondary)
                        .frame(width: 120, alignment: .leading)

                    TextField("YYYY-MM-DD", text: $afterDateText)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 120)

                    Text("Before date")
                        .foregroundStyle(.secondary)
                        .padding(.leading, 18)

                    TextField("YYYY-MM-DD", text: $beforeDateText)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 120)

                    Spacer()
                }
            }

            Text("Exports a tab-delimited CSV with one row per selected account entry. If a grouping account is checked, all of its real-account descendants are included.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if let operationMessage {
                Text(operationMessage)
                    .font(.footnote)
                    .foregroundStyle(.green)
            }

            if let errorMessage {
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

                Button("Export...") {
                    exportReport()
                }
                .disabled(selectedLeafAccountIDs.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 680)
        .onAppear {
            loadAccounts()
            loadDefaultEndDate()
        }
    }

    private func loadAccounts() {
        do {
            let accounts = try appState.accountRepository.getAllAccounts()
            let realAccounts = accounts.filter { account in
                account.class == "asset" || account.class == "liability"
            }
            let realAccountsByParent = Dictionary(grouping: realAccounts, by: \.parentID)

            let roots = realAccounts
                .filter { account in
                    guard let parentID = account.parentID else {
                        return true
                    }
                    return !realAccounts.contains(where: { $0.id == parentID })
                }
                .sorted(by: accountSort)

            accountNodes = roots.map { buildNode(for: $0, childMap: realAccountsByParent) }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadDefaultEndDate() {
        do {
            beforeDateText = try appState.accountReportService.defaultEndDateString()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func buildNode(for account: Account, childMap: [Int64?: [Account]]) -> AccountReportNode {
        let children = (childMap[account.id] ?? [])
            .sorted(by: accountSort)
            .map { buildNode(for: $0, childMap: childMap) }

        return AccountReportNode(account: account, children: children)
    }

    private func accountSort(_ lhs: Account, _ rhs: Account) -> Bool {
        if lhs.sortOrder != rhs.sortOrder {
            return lhs.sortOrder < rhs.sortOrder
        }
        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }

    private func exportReport() {
        guard let afterDate = normalizedDateString(from: afterDateText),
              let beforeDate = normalizedDateString(from: beforeDateText) else {
            errorMessage = "Both dates must use YYYY-MM-DD format."
            operationMessage = nil
            return
        }

        guard afterDate <= beforeDate else {
            errorMessage = "After date must not be later than before date."
            operationMessage = nil
            return
        }

        let panel = NSOpenPanel()
        panel.title = "Choose Report Folder"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser

        guard panel.runModal() == .OK, let directoryURL = panel.url else {
            return
        }

        do {
            let summary = try appState.accountReportService.exportAccountReport(
                selectedLeafAccountIDs: selectedLeafAccountIDs,
                afterDate: afterDate,
                beforeDate: beforeDate,
                destinationDirectoryURL: directoryURL
            )
            operationMessage = "Exported \(summary.exportedRowCount) rows to \(summary.destinationURL.lastPathComponent)."
            errorMessage = nil
        } catch {
            operationMessage = nil
            errorMessage = error.localizedDescription
        }
    }

    private func normalizedDateString(from rawValue: String) -> String? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.dateFormatter.date(from: trimmed) != nil else {
            return nil
        }
        return trimmed
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

private struct AccountReportNodeView: View {
    let node: AccountReportNode
    @Binding var selectedLeafAccountIDs: Set<Int64>

    var body: some View {
        if node.children.isEmpty {
            Toggle(isOn: leafSelectionBinding) {
                Text(node.account.name)
            }
            .toggleStyle(.checkbox)
        } else {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(node.children) { child in
                        AccountReportNodeView(node: child, selectedLeafAccountIDs: $selectedLeafAccountIDs)
                    }
                }
                .padding(.leading, 18)
                .padding(.top, 4)
            } label: {
                Toggle(isOn: groupSelectionBinding) {
                    Text(node.account.name)
                }
                .toggleStyle(.checkbox)
            }
        }
    }

    private var descendantLeafIDs: Set<Int64> {
        if node.children.isEmpty {
            guard let accountID = node.account.id else {
                return []
            }
            return [accountID]
        }

        return Set(node.children.flatMap(descendantLeafIDs(for:)))
    }

    private func descendantLeafIDs(for node: AccountReportNode) -> [Int64] {
        if node.children.isEmpty {
            return node.account.id.map { [$0] } ?? []
        }
        return node.children.flatMap(descendantLeafIDs(for:))
    }

    private var leafSelectionBinding: Binding<Bool> {
        Binding(
            get: {
                guard let accountID = node.account.id else { return false }
                return selectedLeafAccountIDs.contains(accountID)
            },
            set: { isSelected in
                guard let accountID = node.account.id else { return }
                if isSelected {
                    selectedLeafAccountIDs.insert(accountID)
                } else {
                    selectedLeafAccountIDs.remove(accountID)
                }
            }
        )
    }

    private var groupSelectionBinding: Binding<Bool> {
        Binding(
            get: {
                !descendantLeafIDs.isEmpty && descendantLeafIDs.isSubset(of: selectedLeafAccountIDs)
            },
            set: { isSelected in
                if isSelected {
                    selectedLeafAccountIDs.formUnion(descendantLeafIDs)
                } else {
                    selectedLeafAccountIDs.subtract(descendantLeafIDs)
                }
            }
        )
    }
}
