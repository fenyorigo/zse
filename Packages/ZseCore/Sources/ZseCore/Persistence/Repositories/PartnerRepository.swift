import GRDB

struct PartnerRepository {
    private let databaseManager: DatabaseManager

    init(databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager
    }

    func findPartner(named name: String) throws -> Partner? {
        try databaseManager.dbQueue.read { db in
            try findPartner(named: name, db: db)
        }
    }

    func createPartner(_ partner: inout Partner) throws {
        try databaseManager.dbQueue.write { db in
            try partner.insert(db)
        }
    }

    func findPartner(named name: String, db: Database) throws -> Partner? {
        try Partner
            .filter(sql: "LOWER(name) = LOWER(?)", arguments: [name])
            .fetchOne(db)
    }

    func createPartner(_ partner: inout Partner, db: Database) throws {
        try partner.insert(db)
    }
}
