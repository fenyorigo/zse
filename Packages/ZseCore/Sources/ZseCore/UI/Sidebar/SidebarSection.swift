import Foundation

enum SidebarSection: String, CaseIterable, Identifiable {
    case banks
    case creditCards
    case cash
    case investments
    case pensions
    case loans
    case receivables
    case custodial
    case income
    case expenses

    var id: String { rawValue }

    var title: String {
        switch self {
        case .banks:
            return "Banks"
        case .creditCards:
            return "Credit Cards"
        case .cash:
            return "Cash"
        case .investments:
            return "Investments"
        case .pensions:
            return "Pensions"
        case .loans:
            return "Loans"
        case .receivables:
            return "Receivables"
        case .custodial:
            return "Custodial"
        case .income:
            return "Income"
        case .expenses:
            return "Expenses"
        }
    }

    static func from(accountClass: String, accountSubtype: String) -> SidebarSection? {
        switch accountClass {
        case "income":
            return .income
        case "expense":
            return .expenses
        default:
            break
        }

        switch accountSubtype {
        case "bank":
            return .banks
        case "credit":
            return .creditCards
        case "cash":
            return .cash
        case "investment":
            return .investments
        case "pension":
            return .pensions
        case "loan":
            return .loans
        case "receivable":
            return .receivables
        case "custodial":
            return .custodial
        default:
            return nil
        }
    }
}
