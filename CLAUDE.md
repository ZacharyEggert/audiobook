# Ear Reader

iOS 26 audiobook player (SwiftUI, Liquid Glass). Design: `docs/PLAN.md`. Tasks: `docs/ROADMAP.md`. Setup, test and lint commands: `CONTRIBUTING.md`.

## Conventions

- **Generated project**: change `project.yml`, never `EarReader.xcodeproj`, `Info.plist` or `.entitlements`. Run `xcodegen generate` after adding files under `App/`.
- **Colors** come from `Theme` (`App/DesignSystem/Theme.swift`), which is backed by asset color sets. Asset symbol generation is off because the token `primary` collides with SwiftUI's `Color.primary`. A new token needs a color set, a `Theme` entry, and a pair in `AppTests/ContrastTests.swift` if it's used for text.
- **Concurrency**: the app target defaults to `MainActor` isolation (`SWIFT_DEFAULT_ACTOR_ISOLATION`). Packages do not, so mark their types `Sendable` / actor explicitly.
- **Packages**: `MediaParsing` and `AudiobookCore` stay Foundation-only. AVFoundation code goes in `Playback` or `Library`.
- **Test names** use raw identifiers (``@Test func `parses chpl atom`()``); `swiftformat` enforces this.
- **Before finishing**: `swiftformat .`, `swiftlint --strict`, then the tests touched by the change. All three are CI gates.
