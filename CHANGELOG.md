## 1.1.3

Patch release focused on overdue transaction highlighting and warning cleanup behavior.

### Highlights
- Overdue transaction highlighting now updates dynamically in the UI based on the current date
- Imported warning flags remain persistent until the transaction is corrected manually
- Changing a transaction to `Cleared` now reliably removes overdue warning styling
- Changing a transaction date so it is no longer overdue now clears date-based warning flags as well
- Internal cleanup to keep transaction warning behavior consistent across edit paths

## 1.1.2

Patch release focused on persistent hierarchical account visibility and follow-up simplifications.

### Highlights
- Persistent hide and unhide behavior for account hierarchies
- `Show Hidden` remains a temporary view toggle, while `Manage Hidden` edits persistent visibility
- Tree-based `Manage Hidden` sheet with checkbox selection and hierarchy-aware apply behavior
- Parent visibility now follows child visibility consistently across restarts
- Credit-card availability logic consolidated into a shared service for consistency between sidebar and detail views
- Internal code review and simplification pass on account visibility and reporting flows

## 1.1.1

Patch release focused on account visibility management, reporting, and credit-card availability accuracy.

### Highlights
- Right-click hide and unhide support for individual and grouped accounts in the sidebar
- Dedicated hidden-account manager from the sidebar toolbar
- New account report sheet and Reports menu entry
- More accurate available-before-next-reimbursement calculation for credit cards
- Clearer credit availability status coloring in account detail views

## 1.0

First stable release of zse.

### Highlights
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
