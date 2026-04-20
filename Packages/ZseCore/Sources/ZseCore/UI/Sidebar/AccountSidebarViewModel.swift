import Foundation

@MainActor
final class AccountSidebarViewModel: ObservableObject {
    struct HiddenAccountNode: Identifiable {
        let id: Int64
        let account: Account
        let children: [HiddenAccountNode]
        let descendantLeafIDs: Set<Int64>
    }

    struct HiddenAccountOption: Identifiable, Hashable {
        let id: Int64
        let isHidden: Bool
    }

    @Published private(set) var sections: [SidebarSectionModel] = []
    @Published private(set) var lastErrorMessage: String?
    @Published private(set) var reloadRevision = 0
    @Published var showHiddenAccounts = false

    private let accountRepository: AccountRepository
    private let transactionRepository: TransactionRepository
    private let builder: AccountSidebarBuilder
    private let creditCardAvailabilityService: CreditCardAvailabilityService
    private let valuationService: RollupValuationService
    private var accountsByID: [Int64: Account] = [:]

    init(
        accountRepository: AccountRepository,
        transactionRepository: TransactionRepository,
        valuationService: RollupValuationService,
        creditCardAvailabilityService: CreditCardAvailabilityService = CreditCardAvailabilityService(),
        builder: AccountSidebarBuilder = AccountSidebarBuilder()
    ) {
        self.accountRepository = accountRepository
        self.transactionRepository = transactionRepository
        self.valuationService = valuationService
        self.creditCardAvailabilityService = creditCardAvailabilityService
        self.builder = builder
        self.sections = SidebarSection.allCases.map { SidebarSectionModel(section: $0, nodes: []) }
    }

    func reload() {
        do {
            let accounts = try accountRepository.getAllAccounts()
            let balancesByAccountID = try adjustedBalancesByAccountID(accounts: accounts)
            accountsByID = Dictionary(
                uniqueKeysWithValues: accounts.compactMap { account in
                    guard let accountID = account.id else {
                        return nil
                    }
                    return (accountID, account)
                }
            )
            sections = try builder.buildSections(
                from: accounts,
                balancesByAccountID: balancesByAccountID,
                valuationService: valuationService,
                showHiddenAccounts: showHiddenAccounts
            )
            lastErrorMessage = nil
            reloadRevision += 1
        } catch {
            accountsByID = [:]
            sections = SidebarSection.allCases.map { SidebarSectionModel(section: $0, nodes: []) }
            lastErrorMessage = error.localizedDescription
            reloadRevision += 1
        }
    }

    func account(for selection: SidebarSelection?) -> Account? {
        guard let selection else {
            return nil
        }

        guard case let .account(accountID) = selection.kind else {
            return nil
        }

        return accountsByID[accountID]
    }

    func selectionForAccount(id accountID: Int64) -> SidebarSelection? {
        guard let account = accountsByID[accountID] else {
            return nil
        }
        return SidebarSelection(
            id: "account-\(accountID)",
            title: account.name,
            kind: .account(accountID)
        )
    }

    func setShowHiddenAccounts(_ showHiddenAccounts: Bool) {
        guard self.showHiddenAccounts != showHiddenAccounts else {
            return
        }
        self.showHiddenAccounts = showHiddenAccounts
        reload()
    }

    func setHidden(_ isHidden: Bool, accountID: Int64) {
        do {
            try accountRepository.setHidden(isHidden, forAccountID: accountID)
            reload()
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func isSelectionVisible(_ selection: SidebarSelection?) -> Bool {
        guard let selection else {
            return false
        }

        guard case let .account(accountID) = selection.kind else {
            return true
        }

        return sectionsContainsAccount(id: accountID, in: sections)
    }

    func hiddenAccountOptions() -> [HiddenAccountOption] {
        accountsByID.values
            .filter { account in
                account.class == "asset" || account.class == "liability"
            }
            .compactMap { account -> HiddenAccountOption? in
                guard let accountID = account.id else {
                    return nil
                }
                return HiddenAccountOption(
                    id: accountID,
                    isHidden: account.isHidden
                )
            }
            .sorted { lhs, rhs in
                (accountsByID[lhs.id]?.name ?? "").localizedCaseInsensitiveCompare(accountsByID[rhs.id]?.name ?? "") == .orderedAscending
            }
    }

    func hiddenAccountNodes() -> [HiddenAccountNode] {
        let managedAccounts = accountsByID.values.filter { account in
            account.class == "asset" || account.class == "liability"
        }
        let managedAccountIDs = Set(managedAccounts.compactMap(\.id))
        let childMap = Dictionary(grouping: managedAccounts) { account in
            account.parentID
        }

        return managedAccounts
            .filter { account in
                guard let parentID = account.parentID else {
                    return true
                }
                return !managedAccountIDs.contains(parentID)
            }
            .sorted(by: accountSort)
            .map { buildHiddenAccountNode(for: $0, childMap: childMap) }
    }

    func visibleLeafAccountIDs() -> Set<Int64> {
        Set(
            accountsByID.values.compactMap { account in
                guard let accountID = account.id,
                      account.class == "asset" || account.class == "liability",
                      !account.isHidden else {
                    return nil
                }

                let hasManagedChildren = accountsByID.values.contains { candidate in
                    candidate.parentID == accountID &&
                    (candidate.class == "asset" || candidate.class == "liability")
                }
                return hasManagedChildren ? nil : accountID
            }
        )
    }

    func applyVisibleLeafAccountIDs(_ visibleLeafAccountIDs: Set<Int64>) {
        do {
            try accountRepository.applyVisibleLeafAccountIDs(visibleLeafAccountIDs)
            reload()
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func adjustedBalancesByAccountID(accounts: [Account]) throws -> [Int64: Double] {
        var balancesByAccountID = try accountRepository.getAccountBalances()

        for account in accounts {
            guard let accountID = account.id else {
                continue
            }

            let transactions = try transactionRepository.fetchTransactions(forAccountID: accountID)
            guard let snapshot = creditCardAvailabilityService.snapshot(for: account, transactions: transactions),
                  let effectiveUsedCredit = snapshot.effectiveUsedCredit else {
                continue
            }

            balancesByAccountID[accountID] = -effectiveUsedCredit
        }

        return balancesByAccountID
    }

    private func accountPath(for account: Account) -> String {
        var components = [account.name]
        var currentParentID = account.parentID

        while let parentID = currentParentID,
              let parent = accountsByID[parentID] {
            components.append(parent.name)
            currentParentID = parent.parentID
        }

        return components.reversed().joined(separator: " / ")
    }

    private func buildHiddenAccountNode(
        for account: Account,
        childMap: [Int64?: [Account]]
    ) -> HiddenAccountNode {
        let children = (childMap[account.id] ?? [])
            .sorted(by: accountSort)
            .map { buildHiddenAccountNode(for: $0, childMap: childMap) }

        let descendantLeafIDs: Set<Int64>
        if children.isEmpty {
            descendantLeafIDs = account.id.map { [$0] } ?? []
        } else {
            descendantLeafIDs = children.reduce(into: Set<Int64>()) { partialResult, child in
                partialResult.formUnion(child.descendantLeafIDs)
            }
        }

        return HiddenAccountNode(
            id: account.id ?? 0,
            account: account,
            children: children,
            descendantLeafIDs: descendantLeafIDs
        )
    }

    private func accountSort(_ lhs: Account, _ rhs: Account) -> Bool {
        if lhs.sortOrder != rhs.sortOrder {
            return lhs.sortOrder < rhs.sortOrder
        }
        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }

    private func sectionsContainsAccount(id accountID: Int64, in sections: [SidebarSectionModel]) -> Bool {
        sections.contains { section in
            nodesContainAccount(id: accountID, in: section.nodes)
        }
    }

    private func nodesContainAccount(id accountID: Int64, in nodes: [SidebarNode]) -> Bool {
        nodes.contains { node in
            if case let .account(account) = node.kind, account.id == accountID {
                return true
            }
            return nodesContainAccount(id: accountID, in: node.children)
        }
    }
}
