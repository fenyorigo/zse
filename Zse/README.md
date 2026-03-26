# Zse

Zse is a macOS personal-finance app for multi-currency household finance tracking.

It combines:
- hierarchical accounts and categories
- native-currency bookkeeping
- FX-aware rollups
- recurring transactions
- Moneydance import tailored to the current source data

## What It Does

- Tracks asset, liability, income, and expense accounts
- Supports transfers, categorized postings, and recurring transactions
- Keeps native balances while allowing rollup/accumulation in another currency
- Imports Moneydance account trees, balances, transactions, and statuses
- Handles liability-specific presentation such as credit-card flows and repayment tracking

## Current Feature Areas

- Account hierarchy
  - hidden accounts
  - default-expanded account tree
  - opening balances
  - optional accumulation currency on non-leaf/group accounts
- Transactions
  - cleared / pending / uncleared states
  - import warning flags
  - inline amount editing
  - projected recurring transactions in account ledgers
- Credit cards
  - liability-aware In/Out display
  - credit limit
  - available-before-next-reimbursement summary
- Moneydance import
  - account type mapping
  - hierarchy preservation
  - opening balance import
  - transfer detection using known imported real-account paths
  - status mapping and warning metadata

## Project Structure

- `Zse/`
  - Xcode app target, app entry point, wrapper shell
- `../Packages/ZseCore/`
  - domain models
  - persistence and migrations
  - import logic
  - services
  - most UI screens and view models

## Run

1. Open the project in Xcode.
2. Build and run the `Zse` app target.

For development details, testing, and local database paths, see [`DEV.md`](/Users/bajanp/Projects/ZseApp/Zse/DEV.md).

## Notes

The Moneydance importer is intentionally opinionated toward the current Moneydance export structure used for this project. It is not currently positioned as a broad generic importer.
