# Contributing

## Setup

```sh
./scripts/bootstrap.sh   # brew bundle + xcodegen generate
open EarReader.xcodeproj
```

Use the Xcode version in `.xcode-version`. CI runs on it, and other versions print a warning.

## Project file

`EarReader.xcodeproj` is generated from `project.yml` and git-ignored. Run `xcodegen generate` again after you:
- add, move or delete files under `App/` or `AppTests/`
- edit `project.yml` (targets, settings, Info.plist keys, entitlements)
- pull changes that did either of the above

`App/Resources/Info.plist` and `EarReader.entitlements` are also generated. Edit `project.yml` instead.

## Tests

```sh
# Packages: pure Swift, no simulator needed
for p in Packages/*/; do swift test --package-path "$p"; done

# App (same destination as CI)
xcodebuild test -scheme EarReader \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  CODE_SIGNING_ALLOWED=NO
```

New tests use Swift Testing (`@Test`, `#expect`).

## Lint

```sh
swiftformat .          # fixes formatting
swiftlint --strict     # must report 0 violations
```

## Pull requests

`master` is protected. Open a PR from a branch. CI must pass `lint`, `package-tests` and `app-tests` before merging. See [docs/ROADMAP.md](docs/ROADMAP.md) for the task list; each task is one PR.
