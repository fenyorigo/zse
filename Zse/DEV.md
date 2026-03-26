# Development

## Workspace Layout

- `Zse/`
  Xcode-facing app target
- `../Packages/ZseCore/`
  Swift package containing most business logic, persistence, and UI

## Build

Open the workspace/project in Xcode and run the `Zse` app target.

## Tests

Most regression tests currently live in `ZseCore`.

Run from Terminal:

```sh
cd /Users/bajanp/Projects/ZseApp/Packages/ZseCore
swift test
```

## Local Database

The sandboxed app database typically lives at:

```text
~/Library/Containers/net.bajancsalad.Zse/Data/Library/Application Support/net.bajancsalad.zse/
```

Useful file:

```text
~/Library/Containers/net.bajancsalad.Zse/Data/Library/Application Support/net.bajancsalad.zse/zse.sqlite
```

## Import Notes

The Moneydance importer currently assumes the project’s real export structure and uses explicit rules for:
- account hierarchy preservation
- real account vs category separation
- transfer detection
- opening balances
- status mapping and warning flags

## Current Development Themes

- account-tree consistency
- Moneydance import correctness
- liability / credit-card behavior
- FX-aware rollups and accumulation currency
