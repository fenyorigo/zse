import Foundation

struct EntryInput {
    let accountID: Int64
    let amount: Double
    let currency: String
    let partnerID: Int64?
    let memo: String?

    init(
        accountID: Int64,
        amount: Double,
        currency: String,
        partnerID: Int64? = nil,
        memo: String? = nil
    ) {
        self.accountID = accountID
        self.amount = amount
        self.currency = currency
        self.partnerID = partnerID
        self.memo = memo
    }
}
