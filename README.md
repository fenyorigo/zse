zse 1.0 is the first stable release of the app.

## Highlights
- Stable native macOS personal finance app
- Moneydance import validated against live data
- zse flat export/import round-trip implemented and validated
- Correct account and category hierarchy reconstruction
- Credit card limit and available-before-reimbursement support
- Recurring transactions
- FX rate refresh and mixed-currency rollup support
- Backup, restore, and database wipe tools
- Persistent per-account transaction filters
- Balances and portfolio rollups validated against source data

## Notes
- Moneydance import and zse flat import are kept as separate import paths
- zse flat export uses full account and category paths for round-trip stability
- Mixed-currency rollups depend on available FX rates
