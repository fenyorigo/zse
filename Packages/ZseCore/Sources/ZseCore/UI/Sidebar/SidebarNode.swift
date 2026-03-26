import Foundation

struct SidebarSelection: Hashable {
    enum Kind: Hashable {
        case grouping
        case currency
        case account(Int64)
    }

    let id: String
    let title: String
    let kind: Kind
}

struct SidebarSectionModel: Identifiable {
    let section: SidebarSection
    let nodes: [SidebarNode]

    var id: SidebarSection { section }
}

struct SidebarNode: Identifiable {
    enum Kind {
        case grouping
        case currency(code: String)
        case account(Account)
    }

    let id: String
    let title: String
    let kind: Kind
    let children: [SidebarNode]
    let balanceValue: Double?
    let balanceCurrency: String?

    var selection: SidebarSelection? {
        switch kind {
        case .grouping:
            return SidebarSelection(id: id, title: title, kind: .grouping)
        case .currency:
            return SidebarSelection(id: id, title: title, kind: .currency)
        case .account(let account):
            guard let accountID = account.id else {
                return nil
            }
            return SidebarSelection(id: id, title: title, kind: .account(accountID))
        }
    }

    var account: Account? {
        guard case let .account(account) = kind else {
            return nil
        }
        return account
    }

    var isSelectable: Bool {
        selection != nil
    }

    var formattedBalance: String? {
        guard let balanceValue, let balanceCurrency else {
            return nil
        }

        let displayedValue: Double
        switch kind {
        case .account(let account) where account.class == "income" || account.class == "liability":
            displayedValue = -balanceValue
        default:
            displayedValue = balanceValue
        }

        let formattedNumber = Self.balanceFormatter.string(from: NSNumber(value: displayedValue))
            ?? String(format: "%.2f", displayedValue)
        return "\(formattedNumber) \(balanceCurrency)"
    }

    private static let balanceFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter
    }()
}
