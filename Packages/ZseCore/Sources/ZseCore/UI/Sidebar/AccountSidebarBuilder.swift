import Foundation

struct AccountSidebarBuilder {
    func buildSections(
        from accounts: [Account],
        balancesByAccountID: [Int64: Double],
        valuationService: RollupValuationService,
        showHiddenAccounts: Bool
    ) throws -> [SidebarSectionModel] {
        let allAccountsByID: [Int64: Account] = Dictionary(
            uniqueKeysWithValues: accounts.compactMap { account in
                guard let accountID = account.id else {
                    return nil
                }
                return (accountID, account)
            }
        )

        let visibleAccounts = accounts.filter { account in
            isVisible(account: account, accountsByID: allAccountsByID, showHiddenAccounts: showHiddenAccounts)
        }

        let accountsByID: [Int64: Account] = Dictionary(
            uniqueKeysWithValues: visibleAccounts.compactMap { account in
                guard let accountID = account.id else {
                    return nil
                }
                return (accountID, account)
            }
        )

        let childMap = Dictionary(grouping: visibleAccounts) { account in
            account.parentID
        }

        var sectionModels: [SidebarSectionModel] = []
        for section in SidebarSection.allCases {
            let nodes = try buildSectionNodes(
                for: section,
                accountsByID: accountsByID,
                childMap: childMap,
                balancesByAccountID: balancesByAccountID,
                valuationService: valuationService
            )
            sectionModels.append(SidebarSectionModel(section: section, nodes: nodes))
        }
        return sectionModels
    }

    private func isVisible(
        account: Account,
        accountsByID: [Int64: Account],
        showHiddenAccounts: Bool
    ) -> Bool {
        guard !showHiddenAccounts else {
            return true
        }

        if account.isHidden {
            return false
        }

        var currentParentID = account.parentID
        while let parentID = currentParentID, let parent = accountsByID[parentID] {
            if parent.isHidden {
                return false
            }
            currentParentID = parent.parentID
        }

        return true
    }

    private func buildSectionNodes(
        for section: SidebarSection,
        accountsByID: [Int64: Account],
        childMap: [Int64?: [Account]],
        balancesByAccountID: [Int64: Double],
        valuationService: RollupValuationService
    ) throws -> [SidebarNode] {
        let sectionAccounts = accountsByID.values.filter { account in
            sectionForAccount(account, childMap: childMap) == section
        }

        let rootAccounts = sectionAccounts.filter { account in
            guard let parentID = account.parentID,
                  let parentAccount = accountsByID[parentID] else {
                return true
            }
            return sectionForAccount(parentAccount, childMap: childMap) != section
        }
        .sorted(by: accountSort)

        var rootNodes: [SidebarNode] = []
        for account in rootAccounts {
            if let node = try buildNode(
                for: account,
                section: section,
                childMap: childMap,
                balancesByAccountID: balancesByAccountID,
                valuationService: valuationService
            ) {
                rootNodes.append(node)
            }
        }
        return rootNodes
    }

    private func buildNode(
        for account: Account,
        section: SidebarSection,
        childMap: [Int64?: [Account]],
        balancesByAccountID: [Int64: Double],
        valuationService: RollupValuationService
    ) throws -> SidebarNode? {
        guard let accountID = account.id else {
            return nil
        }

        let sectionChildren = (childMap[accountID] ?? [])
            .filter { child in
                sectionForAccount(child, childMap: childMap) == section
            }
            .sorted(by: accountSort)

        var childNodes: [SidebarNode] = []
        for child in sectionChildren {
            if let childNode = try buildNode(
                for: child,
                section: section,
                childMap: childMap,
                balancesByAccountID: balancesByAccountID,
                valuationService: valuationService
            ) {
                childNodes.append(childNode)
            }
        }

        let ownBalance = account.isGroup ? 0 : (balancesByAccountID[accountID] ?? 0)
        let rollupCurrency = account.accumulationCurrency ?? account.currency

        if account.isGroup || !childNodes.isEmpty {
            let aggregateBalance = try aggregateBalance(
                ownCurrency: account.currency,
                ownBalance: ownBalance,
                childNodes: childNodes,
                rollupCurrency: rollupCurrency,
                valuationService: valuationService
            )

            return SidebarNode(
                id: "account-\(accountID)",
                title: account.name,
                kind: .account(account),
                children: childNodes,
                balanceValue: aggregateBalance,
                balanceCurrency: rollupCurrency
            )
        }

        return SidebarNode(
            id: "account-\(accountID)",
            title: account.name,
            kind: .account(account),
            children: [],
            balanceValue: ownBalance,
            balanceCurrency: account.currency
        )
    }

    private func aggregateBalance(
        ownCurrency: String,
        ownBalance: Double,
        childNodes: [SidebarNode],
        rollupCurrency: String,
        valuationService: RollupValuationService
    ) throws -> Double? {
        var total = 0.0

        if abs(ownBalance) > 0.000001 {
            guard let convertedOwnBalance = try valuationService.convert(
                amount: ownBalance,
                from: ownCurrency,
                to: rollupCurrency
            ) else {
                return nil
            }
            total += convertedOwnBalance
        }

        for childNode in childNodes {
            guard let childBalance = childNode.balanceValue,
                  let childCurrency = childNode.balanceCurrency else {
                return nil
            }

            guard let convertedChildBalance = try valuationService.convert(
                amount: childBalance,
                from: childCurrency,
                to: rollupCurrency
            ) else {
                return nil
            }

            total += convertedChildBalance
        }

        return total
    }

    private func sectionForAccount(
        _ account: Account,
        childMap: [Int64?: [Account]]
    ) -> SidebarSection? {
        if let section = SidebarSection.from(
            accountClass: account.class,
            accountSubtype: account.subtype
        ) {
            return section
        }

        guard let accountID = account.id else {
            return nil
        }

        let descendantSections = Set(
            descendants(of: accountID, childMap: childMap).compactMap { descendant in
                sectionForAccount(descendant, childMap: childMap)
            }
        )

        guard descendantSections.count == 1 else {
            return nil
        }

        return descendantSections.first
    }

    private func descendants(
        of accountID: Int64,
        childMap: [Int64?: [Account]]
    ) -> [Account] {
        let children = childMap[accountID] ?? []
        let nestedDescendants: [Account] = children.flatMap { child in
            guard let childID = child.id else {
                return [Account]()
            }
            return descendants(of: childID, childMap: childMap)
        }
        return children + nestedDescendants
    }

    private func accountSort(_ lhs: Account, _ rhs: Account) -> Bool {
        if lhs.sortOrder != rhs.sortOrder {
            return lhs.sortOrder < rhs.sortOrder
        }
        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }
}
