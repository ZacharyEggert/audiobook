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

## Releasing

Signing uses [fastlane match](https://docs.fastlane.tools/actions/match/): the App Store certificate and profile are stored encrypted in a private certificates repo. Ruby comes from `.ruby-version`; install the pinned fastlane with `bundle install`.

Copy `fastlane/.env.example` to `fastlane/.env` and fill it in (it is git-ignored). Then:

```sh
# Once, to create the certificate and profile. Needs write access to the certificates repo.
bundle exec fastlane certificates

# Build, sign and upload. Regenerates the project and switches the app target to the match profile.
bundle exec fastlane release version:0.1.0 destination:testflight notes:"What's new"
```

The version you pass sets `MARKETING_VERSION`. The build number is the latest TestFlight build + 1, across all versions. Run `xcodegen generate` afterwards to get automatic signing back for development.

### From GitHub Actions

Actions → **Release** → Run workflow on `master`, with a version, a destination (`testflight` or `app-store-review`) and release notes. The workflow:

1. checks the version is `X.Y.Z` and greater than the last `v*` tag
2. runs the full CI suite (`ci.yml` via `workflow_call`)
3. runs `fastlane release` in the `production` environment, which holds the secrets (`ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8_BASE64`, `MATCH_PASSWORD`, `MATCH_GIT_URL`, `MATCH_DEPLOY_KEY`)
4. tags `v<version>` and creates a GitHub Release with the notes and the zipped dSYMs
