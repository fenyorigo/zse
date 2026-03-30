import GRDB

enum Migrations {
    static let defaultCurrencies: [Currency] = [
        Currency(code: "HUF", name: "Hungarian Forint", symbol: "Ft", decimals: 0),
        Currency(code: "EUR", name: "Euro", symbol: "EUR", decimals: 2),
        Currency(code: "USD", name: "US Dollar", symbol: "$", decimals: 2),
        Currency(code: "GBP", name: "British Pound", symbol: "GBP", decimals: 2),
        Currency(code: "CZK", name: "Czech Koruna", symbol: "CZK", decimals: 2),
        Currency(code: "RON", name: "Romanian Leu", symbol: "RON", decimals: 2),
        Currency(code: "PLN", name: "Polish Zloty", symbol: "PLN", decimals: 2)
    ]

    static let migrator: DatabaseMigrator = {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("createCoreTables") { db in
            try db.create(table: "currencies") { table in
                table.column("code", .text).primaryKey()
                table.column("name", .text).notNull()
                table.column("symbol", .text)
                table.column("decimals", .integer).notNull().defaults(to: 2)
            }

            try db.create(table: "accounts") { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("parent_id", .integer)
                    .references("accounts", onDelete: .setNull)
                table.column("name", .text).notNull()
                table.column("class", .text).notNull()
                table.column("subtype", .text).notNull()
                table.column("currency", .text).notNull()
                    .references("currencies", column: "code")
                table.column("is_group", .boolean).notNull().defaults(to: false)
                table.column("include_in_net_worth", .boolean).notNull().defaults(to: true)
                table.column("sort_order", .integer).defaults(to: 0)
                table.column("created_at", .text).notNull()
                table.column("updated_at", .text).notNull()
            }

            try db.create(index: "idx_accounts_parent_id", on: "accounts", columns: ["parent_id"])

            try db.create(table: "partners") { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("name", .text).notNull()
                table.column("notes", .text)
                table.column("is_active", .boolean).notNull().defaults(to: true)
            }

            try db.create(table: "transactions") { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("txn_date", .text).notNull()
                table.column("description", .text)
                table.column("state", .text).notNull().defaults(to: "uncleared")
                table.column("created_at", .text).notNull()
                table.column("updated_at", .text).notNull()
            }

            try db.create(table: "entries") { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("transaction_id", .integer).notNull()
                    .references("transactions", onDelete: .cascade)
                table.column("account_id", .integer).notNull()
                    .references("accounts")
                table.column("amount", .double).notNull()
                table.column("currency", .text).notNull()
                    .references("currencies", column: "code")
                table.column("partner_id", .integer)
                    .references("partners")
                table.column("memo", .text)
                table.column("created_at", .text).notNull()
            }

            try db.create(index: "idx_entries_transaction_id", on: "entries", columns: ["transaction_id"])
            try db.create(index: "idx_entries_account_id", on: "entries", columns: ["account_id"])

            for currency in defaultCurrencies {
                try currency.insert(db)
            }
        }

        migrator.registerMigration("createFxRates") { db in
            try db.create(table: "fx_rates") { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("rate_date", .text).notNull()
                table.column("currency_code", .text).notNull()
                    .references("currencies", column: "code")
                table.column("huf_rate", .double).notNull()
                table.column("source", .text).notNull().defaults(to: "MNB")
                table.column("downloaded_at", .text).notNull()
                table.uniqueKey(["rate_date", "currency_code", "source"])
            }

            try db.create(index: "idx_fx_rates_lookup", on: "fx_rates", columns: [
                "currency_code",
                "rate_date",
                "source"
            ])
        }

        migrator.registerMigration("createRecurringRules") { db in
            try db.create(table: "recurring_rules") { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("name", .text).notNull()
                table.column("transaction_type", .text).notNull()
                table.column("source_account_id", .integer)
                    .references("accounts", onDelete: .setNull)
                table.column("target_account_id", .integer)
                    .references("accounts", onDelete: .setNull)
                table.column("category_account_id", .integer)
                    .references("accounts", onDelete: .setNull)
                table.column("amount", .double).notNull()
                table.column("currency", .text).notNull()
                    .references("currencies", column: "code")
                table.column("description", .text)
                table.column("memo", .text)
                table.column("default_state", .text).notNull().defaults(to: "uncleared")
                table.column("recurrence_type", .text).notNull()
                table.column("interval_n", .integer).notNull().defaults(to: 1)
                table.column("day_of_month", .integer)
                table.column("start_date", .text).notNull()
                table.column("end_date", .text)
                table.column("next_due_date", .text)
                table.column("is_active", .boolean).notNull().defaults(to: true)
                table.column("created_at", .text).notNull()
                table.column("updated_at", .text).notNull()
            }

            try db.create(index: "idx_recurring_rules_next_due_date", on: "recurring_rules", columns: [
                "is_active",
                "next_due_date"
            ])

            try db.alter(table: "transactions") { table in
                table.add(column: "recurring_rule_id", .integer)
                    .references("recurring_rules", onDelete: .setNull)
                table.add(column: "recurring_occurrence_date", .text)
            }

            try db.create(
                index: "idx_transactions_recurring_occurrence_unique",
                on: "transactions",
                columns: ["recurring_rule_id", "recurring_occurrence_date"],
                options: [.unique]
            )
        }

        migrator.registerMigration("extendRecurringRulesWithEndModes") { db in
            try db.alter(table: "recurring_rules") { table in
                table.add(column: "end_mode", .text).notNull().defaults(to: "none")
                table.add(column: "max_occurrences", .integer)
            }
        }

        migrator.registerMigration("addOpeningBalanceToAccounts") { db in
            try db.alter(table: "accounts") { table in
                table.add(column: "opening_balance", .double)
                table.add(column: "opening_balance_date", .text)
            }
        }

        migrator.registerMigration("addTransactionStatusWarnings") { db in
            try db.alter(table: "transactions") { table in
                table.add(column: "status_warning_flag", .boolean).notNull().defaults(to: false)
                table.add(column: "status_warning_reason", .text)
            }
        }

        migrator.registerMigration("addAccountHiddenFlag") { db in
            try db.alter(table: "accounts") { table in
                table.add(column: "is_hidden", .boolean).notNull().defaults(to: false)
            }
        }

        migrator.registerMigration("addAccountAccumulationCurrency") { db in
            try db.alter(table: "accounts") { table in
                table.add(column: "accumulation_currency", .text)
                    .references("currencies", column: "code")
            }
        }

        migrator.registerMigration("addAccountCreditLimit") { db in
            try db.alter(table: "accounts") { table in
                table.add(column: "credit_limit", .double)
            }
        }

        migrator.registerMigration("addAccountCreditAvailabilityWarningPercent") { db in
            try db.alter(table: "accounts") { table in
                table.add(column: "credit_availability_warning_percent", .double)
            }
        }

        migrator.registerMigration("createAppPreferences") { db in
            try db.create(table: "app_preferences") { table in
                table.column("id", .integer).primaryKey()
                table.column("backup_directory_path", .text)
                table.column("backup_directory_bookmark_data", .blob)
                table.column("created_at", .text).notNull()
                table.column("updated_at", .text).notNull()
            }

            var preferences = AppPreferences()
            try preferences.insert(db)
        }

        migrator.registerMigration("createAccountUIPreferences") { db in
            try db.create(table: "account_ui_preferences") { table in
                table.column("account_id", .integer).primaryKey()
                    .references("accounts", onDelete: .cascade)
                table.column("transaction_status_filter", .text)
                table.column("created_at", .text).notNull()
                table.column("updated_at", .text).notNull()
            }
        }

        migrator.registerMigration("addDateFiltersToAccountUIPreferences") { db in
            try db.alter(table: "account_ui_preferences") { table in
                table.add(column: "after_date_filter", .text)
                table.add(column: "before_date_filter", .text)
            }
        }

        migrator.registerMigration("addBackupDirectoryBookmarkToAppPreferences") { db in
            try db.alter(table: "app_preferences") { table in
                table.add(column: "backup_directory_bookmark_data", .blob)
            }
        }

        return migrator
    }()
}
