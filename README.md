# Pub

Pub is a native macOS SwiftUI app for browsing, installing, removing, and upgrading Homebrew formulas and casks.

It is intentionally simple: Pub talks directly to the local `brew` CLI, shows package state clearly, and keeps command output visible when work is in progress.

## Features

- Browse installed formulas and casks with version, status, tap, alias, dependency, and caveat details
- Highlight outdated packages and upgrade everything from one place
- Search the Homebrew catalog before installing something new
- Stream live `brew` output during installs, upgrades, and removals
- Stay native to macOS with a SwiftUI interface and no Electron layer

## Requirements

- macOS 14 or later
- Homebrew installed locally
- `brew` available in one of these locations:
  - `/opt/homebrew/bin/brew`
  - `/usr/local/bin/brew`
  - anywhere on your `PATH`

Pub reads your local Homebrew state directly. It does not automatically run `brew update`.

## Run Locally

Open `Package.swift` in Xcode 26 or newer and run the `Pub` executable target.

You can also build from Terminal:

```bash
swift build
swift test
swift run Pub
```

## Install From Releases

GitHub releases publish an unsigned `.dmg` containing `Pub.app`.

To install:

1. Download the latest `.dmg` from the Releases page.
2. Open the disk image.
3. Drag `Pub.app` into `Applications`.

## Open an Unsigned macOS App

Because release builds are unsigned, macOS will usually block the first launch.

The quickest path is:

1. Move `Pub.app` into `/Applications`.
2. Control-click the app and choose `Open`.
3. Confirm the prompt.

If macOS still blocks the app:

1. Try to open `Pub.app` once.
2. Open `System Settings > Privacy & Security`.
3. Find the security message for Pub near the bottom of the page.
4. Click `Open Anyway`.
5. Launch the app again and confirm.

Only bypass Gatekeeper for builds you trust.

## Release Process

This repository uses Release Please to manage version bumps, changelog updates, tags, and GitHub releases.

- Use conventional commits for release-worthy changes.
- `feat:` produces a minor release.
- `fix:` and `deps:` produce a patch release.
- Breaking changes should use `!` or a `BREAKING CHANGE:` footer.

When releasable commits land on `main`, Release Please opens or updates a release PR. Merging that PR updates the version files, creates the tag, and creates the GitHub release. A separate workflow then builds and uploads the macOS `.dmg`.

Release Please defaults to `GITHUB_TOKEN`, but its own docs note that releases created that way do not trigger downstream workflows such as `release.published`. To make the DMG workflow run automatically, set a repository secret named `RELEASE_PLEASE_TOKEN` with a token that can create releases.

## Project Layout

- `Sources/Pub`: SwiftUI app, state model, Homebrew service layer, and views
- `Tests/PubTests`: decoding and parsing coverage for the Homebrew integration layer
- `.github/workflows/release-please.yml`: versioning, changelog, tag, and GitHub release automation
- `.github/workflows/release-dmg.yml`: release-triggered DMG packaging and asset upload
- `scripts/build-dmg.sh`: creates `Pub.app`, wraps it in a `.dmg`, and emits checksums

## Notes

- Pub expects the Homebrew CLI to be installed already.
- Refreshing reads the current local package state only.
- The app is currently distributed as unsigned macOS builds.
