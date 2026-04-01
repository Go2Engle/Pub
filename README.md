# Pub

Pub is a native macOS SwiftUI app for viewing, managing, installing, and upgrading Homebrew formulas and casks.

## What it does

- Lists installed Homebrew formulas and casks with version and status badges
- Highlights outdated packages and supports one-click upgrades
- Searches the Homebrew catalog for packages to install
- Streams `brew` command output inside the app for installs, upgrades, and removals

## Project shape

- `Sources/Pub`: SwiftUI app, state model, Homebrew service layer, and views
- `Tests/PubTests`: decoding and parsing coverage for the Homebrew integration layer

## Running it

1. Open `Package.swift` in Xcode 26 or later.
2. Run the `Pub` executable target as a macOS app.

You can also build from Terminal:

```bash
swift build
```

## Notes

- Pub talks directly to the local Homebrew CLI and expects `brew` to exist in `/opt/homebrew/bin`, `/usr/local/bin`, or `PATH`.
- Refreshing reads the current local Homebrew state. It does not automatically run `brew update`.
