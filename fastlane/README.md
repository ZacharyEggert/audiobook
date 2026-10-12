fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## iOS

### ios certificates

```sh
[bundle exec] fastlane ios certificates
```

One-time, local: create the App Store certificate and profile in the match repo.

Needs write access to the certificates repo (the CI deploy key is read-only).

### ios release

```sh
[bundle exec] fastlane ios release
```

Build and upload a release.

Options: version:0.1.0 destination:testflight|app-store-review notes:"..."

notes falls back to $RELEASE_NOTES.

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
