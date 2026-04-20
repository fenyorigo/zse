zse 1.1.1 is a focused usability update with hidden-account management, account reporting, and more accurate credit-card availability forecasting.

## Highlights
- Right-click hide and unhide support in the account sidebar
- Dedicated hidden-account manager from the sidebar toolbar
- New account report sheet with a Reports menu entry
- Improved available-before-next-reimbursement calculation for credit cards
- Clearer credit availability status coloring in account detail views

## Notes
- Hidden-account management currently applies to asset and liability accounts
- Account reports are generated from selected account leaves and date bounds

zse 1.1 improves day-to-day usability with persistent filtering, better credit-card monitoring, and a new balance chart view for accounts and subaccounts.

## Highlights
- Per-account date range filters, persisted across app restarts
- Credit card availability warning threshold with visual highlighting
- Stacked area balance charts for accounts and relevant subaccounts
- List / Chart toggle in account detail views
- Improved chart timeline scaling and labeling
- Chart support for postable leaf accounts
- Corrected chart direction for income-category views
- Additional import and UI stability refinements

## Notes
- Balance charts are state/balance charts, not performance charts
- Charts work best on homogeneous-currency subtrees
- Moneydance import and zse flat import remain separate manual import paths

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
