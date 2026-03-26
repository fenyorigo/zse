import Foundation

@MainActor
final class AccountSidebarViewModel: ObservableObject {
    @Published private(set) var sections: [SidebarSectionModel] = []
    @Published private(set) var lastErrorMessage: String?
    @Published var showHiddenAccounts = false

    private let accountRepository: AccountRepository
    private let builder: AccountSidebarBuilder
    private let valuationService: RollupValuationService
    private var accountsByID: [Int64: Account] = [:]

    init(
        accountRepository: AccountRepository,
        valuationService: RollupValuationService,
        builder: AccountSidebarBuilder = AccountSidebarBuilder()
    ) {
        self.accountRepository = accountRepository
        self.valuationService = valuationService
        self.builder = builder
        self.sections = SidebarSection.allCases.map { SidebarSectionModel(section: $0, nodes: []) }
    }

    func reload() {
        do {
            let accounts = try accountRepository.getAllAccounts()
            let balancesByAccountID = try accountRepository.getAccountBalances()
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
        } catch {
            accountsByID = [:]
            sections = SidebarSection.allCases.map { SidebarSectionModel(section: $0, nodes: []) }
            lastErrorMessage = error.localizedDescription
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
}
