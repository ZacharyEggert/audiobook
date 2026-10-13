# Ear Reader — Implementation Plan

**Ear Reader** is a native iOS audiobook player for DRM-free files the user owns. Its layout takes cues from Audible: a dark blue primary color on cool grey backgrounds, built with iOS 26 **Liquid Glass**. CI runs tests on every PR, and a GitHub Action that is started by hand does the release.

### Decisions

| | |
|---|---|
| App name | **Ear Reader** |
| Bundle ID | `llc.ex-nihilo.audiobook` (widget: `.widgets`, App Group `group.llc.ex-nihilo.audiobook`) |
| Minimum OS | **iOS 26** (Xcode 26, Swift 6.2) |
| Visual language | Liquid Glass (system glass for navigation and controls, solid content layer) |
| Language | Swift only |
| Imports | Always **copied** into the library folder |
| iCloud | Syncs the **whole library**: audio (iCloud Drive), book records, progress, bookmarks and collections. A book imported on one device plays and resumes on another |
| Out of scope for v1 | Audiobookshelf/Plex/WebDAV servers, Ogg/Opus playback, DRM formats |
| Apple Developer account | Live |

See [ROADMAP.md](ROADMAP.md) for the task-level breakdown.

---

## 1. Technology choices

| Concern | Choice | Why |
|---|---|---|
| Language / UI | Swift 6.2 (strict concurrency, approachable-concurrency defaults with main-actor isolation for the app target), SwiftUI, `@Observable` | Background audio, Now Playing, CarPlay, Liquid Glass and AVFoundation chapter APIs are first-class in native code |
| Minimum OS | iOS 26 | Liquid Glass APIs (`glassEffect`, `GlassEffectContainer`, `tabViewBottomAccessory`), latest SwiftData, App Intents and Control Center controls. No availability checks needed |
| Persistence | SwiftData, mirrored to CloudKit (private database); audio files in the app's iCloud Drive container | Position can only sync if the book it belongs to syncs too, so records and audio sync together |
| Playback | AVFoundation (`AVQueuePlayer`), plus an `AVAudioEngine`-based decoder engine for non-native formats | See §3 |
| System integration | MediaPlayer (`MPNowPlayingInfoCenter`, `MPRemoteCommandCenter`), CarPlay, WidgetKit, App Intents | |
| Project generation | **XcodeGen** (`project.yml`, with the `.xcodeproj` git-ignored) | No `.pbxproj` merge conflicts; deterministic CI |
| Modularity | Local Swift packages | Parsers and domain logic can be tested with `swift test`, without a simulator |
| Lint / format | SwiftLint + SwiftFormat | Enforced in CI |
| Tests | Swift Testing (unit), XCTest/XCUITest (UI), swift-snapshot-testing | |
| Release | fastlane (`match`, `gym`, `pilot`) run from a `workflow_dispatch` action | |
| Third-party deps (kept minimal) | ZIPFoundation (zip import), swift-snapshot-testing (tests only) | |

---

## 2. Repository layout

```
audiobook/
├── project.yml                  # XcodeGen spec (app, widget ext, test targets)
├── App/                         # iOS app target (thin: composition root + feature UI)
│   ├── AudiobookApp.swift
│   ├── Features/
│   │   ├── Home/                # Continue Listening hero, recent, series rows
│   │   ├── Library/             # Titles / Authors / Series / Narrators / Collections
│   │   ├── Player/              # MiniPlayer, FullPlayer, ChapterList, Bookmarks, SleepTimer
│   │   ├── BookDetail/
│   │   ├── Import/
│   │   ├── Stats/
│   │   └── Settings/
│   ├── DesignSystem/            # Theme tokens, typography, components (CoverView, ProgressRing…)
│   ├── CarPlay/                 # CPTemplateApplicationSceneDelegate
│   └── Resources/               # Assets.xcassets (color sets), Info.plist, entitlements
├── Widgets/                     # WidgetKit extension (Continue Listening, Lock Screen)
├── Packages/
│   ├── MediaParsing/            # Pure Swift: MP4 boxes, ID3v2, FLAC/Vorbis, CUE, OverDrive markers
│   ├── AudiobookCore/           # Domain models, BookTimeline math, grouping heuristics
│   ├── Playback/                # PlaybackEngine protocol, AVPlayerEngine, NowPlaying, SleepTimer
│   └── Library/                 # Import pipeline, SwiftData store, file management
├── Tests/
│   ├── Fixtures/                # Tiny generated audio files (committed, < 2 MB total)
│   ├── AppUITests/
│   └── SnapshotTests/
├── scripts/
│   ├── make-fixtures.sh         # ffmpeg recipes that regenerate Tests/Fixtures
│   └── bootstrap.sh             # brew bundle + xcodegen generate
├── fastlane/                    # Fastfile, Appfile, Matchfile
├── Brewfile                     # xcodegen, swiftlint, swiftformat, ffmpeg
└── .github/workflows/
    ├── ci.yml
    └── release.yml
```

---

## 3. Audio format support (the core problem)

### 3.1 Format matrix

| Format | Playback | Chapter source(s) | Notes |
|---|---|---|---|
| **.m4b / .m4a / .aac / .mp4** (AAC, ALAC, xHE-AAC) | AVFoundation | QuickTime chapter track (the `tref/chap` text track, read by our own MP4 box parser so `MediaParsing` stays Foundation-only). Falls back to the **Nero `chpl` atom**, which AVFoundation ignores | This is the main audiobook format. Many tools (e.g. some m4b-tool outputs, older Nero encoders) write only `chpl`. |
| **.mp3** (single file) | AVFoundation | **ID3v2 `CHAP`/`CTOC` frames** (our own parser; AVFoundation doesn't expose them reliably). Also OverDrive `TXXX:OverDrive MediaMarkers` | Use `AVURLAssetPreferPreciseDurationAndTimingKey = true` for accurate VBR seeking; read the Xing/LAME header for duration |
| **Folder of .mp3** (or .m4a / .flac) | AVFoundation via `AVQueuePlayer` | One chapter per file, titled from ID3 `TIT2` or a cleaned-up filename. If files have internal chapters, those are concatenated with offsets | The most common "collection" case. Multi-disc subfolders (`CD1`, `Disc 2`, `Part 03`) are merged into one book |
| **.flac** | AVFoundation (iOS 11+) | Vorbis comments `CHAPTER001=00:00:00.000` / `CHAPTER001NAME=` | |
| **.wav / .aiff / .caf** | AVFoundation | none, or a CUE sidecar | |
| **.opus / .ogg (Vorbis/Opus)** | ✗ (out of scope for v1) | — | AVFoundation can't demux Ogg. Detected and reported as unsupported. The `PlaybackEngine` protocol leaves room for a decoder-based engine later |
| **Single file + .cue sidecar** | Any of the above | CUE `TRACK`/`INDEX 01` | |
| **.zip** of any of the above | Extracted on import (ZIPFoundation) | — | |
| .aax / .aaxc (Audible DRM), .wma | ✗ | — | Detected and reported as "unsupported (DRM / codec)". DRM removal is out of scope |

### 3.2 Chapter resolution order (per book)

1. Embedded chapters: QuickTime track → Nero `chpl` → ID3 `CHAP` → Vorbis `CHAPTERxxx`
2. A `.cue` sidecar next to the audio
3. OverDrive MediaMarkers
4. Multi-file book: one chapter per file (each file's internal chapters are expanded if present)
5. Fallback: a single chapter covering the whole book

`MediaParsing` returns `[RawChapter(start, title, sourceFile)]`. `AudiobookCore` turns these into a book-global list, drops zero-length or duplicate entries, and clamps each chapter's end to the next chapter's start (or the file's end).

### 3.3 Metadata mapping

| Field | MP4 | ID3v2 | Vorbis |
|---|---|---|---|
| Title | `©alb` → `©nam` | `TALB` → `TIT2` | `ALBUM` → `TITLE` |
| Author | `aART` → `©ART` | `TPE2` → `TPE1` | `ALBUMARTIST` → `ARTIST` |
| Narrator | `©nrt`, `©wrt`/`©cmp` | `TXXX:NARRATOR`, `TCOM` | `NARRATOR`, `COMPOSER` |
| Series / # | `©mvn`/`©mvi`, `----:com.apple.iTunes:SERIES` | `TXXX:SERIES`, `TXXX:SERIES-PART`, `MVNM`/`MVIN` | `SERIES`, `SERIESPART` |
| Description | `desc`/`ldes` | `COMM`, `TXXX:DESCRIPTION` | `DESCRIPTION` |
| Year, Genre, Publisher | `©day`, `©gen`, `©pub` | `TDRC`/`TYER`, `TCON`, `TPUB` | `DATE`, `GENRE`, `ORGANIZATION` |
| Cover | `covr` | `APIC` (front cover preferred) | `METADATA_BLOCK_PICTURE` |

Cover fallback: `cover.jpg|png`, `folder.jpg`, then the largest image in the folder. Covers are downscaled and cached at 3 sizes (list, grid, player).

### 3.4 Unified timeline model

```swift
struct Book {          // SwiftData @Model in Library, plain struct in Core
  id, title, authors, narrators, series, seriesIndex, coverRef, ...
  files: [AudioFile]   // ordered
  chapters: [Chapter]  // book-global times
  duration: TimeInterval
}
struct AudioFile { id, relativePath, duration, globalOffset, format }
struct Chapter   { index, title, start, end }   // global seconds
struct BookTimeline {
  func locate(_ global: TimeInterval) -> (fileIndex: Int, local: TimeInterval)
  func global(fileIndex: Int, local: TimeInterval) -> TimeInterval
  func chapter(at global: TimeInterval) -> Chapter
}
```

All UI and persistence work in **global book time**. Only the engine deals with file-local time. `BookTimeline` is pure and heavily unit-tested.

### 3.5 Book grouping heuristics (import)

- A standalone audio file with chapters, or one ≥ 20 min long, becomes **one book**.
- A folder whose direct children are audio files becomes one book. Subfolders matching `/(cd|disc|disk|part)\s*\d+/i` are merged into the parent book, ordered by that number.
- A folder holding several `.m4b` files gives one book per file, unless the files share an album tag and have part numbering.
- File order: disc number → track number → `localizedStandardCompare` (natural sort) on filename.
- If album/artist tags disagree inside a folder, flag the book for review.
- Users can **merge, split, reorder files and edit metadata** after import. Manual edits are stored as overrides, so a re-scan doesn't clobber them.

---

## 4. Playback engine

```swift
protocol PlaybackEngine: AnyObject, Sendable {
  func load(_ book: Book, at global: TimeInterval) async throws
  func play(); func pause()
  func seek(to global: TimeInterval) async
  var rate: Float { get set }            // 0.5 … 3.5, step 0.05
  var events: AsyncStream<PlaybackEvent> { get }  // time, state, chapter change, item end, error
}
```

- **AVPlayerEngine**: `AVQueuePlayer` loaded with the remaining files from the current one onward. Seeking within the current file uses `seek(to:toleranceBefore:.zero,toleranceAfter:.zero)`; seeking into a different file rebuilds the queue. Next items are prerolled so playback is gapless across MP3 boundaries. `audioTimePitchAlgorithm = .timeDomain` keeps voices natural at speed.
- *Future:* an `AVAudioEngine`-based engine (`AVAudioPlayerNode` + `AVAudioUnitTimePitch`) would allow Ogg/Opus, **volume boost** and **voice EQ / silence trimming**. It is not part of v1.
- **PlayerController** (`@Observable`, `@MainActor`): the single source of truth for the UI. It owns the engine, the current book, chapter and position.
- **Audio session**: `.playback` category, `.spokenAudio` mode, and the background audio capability. It handles:
  - interruptions (calls, Siri): pause, then resume if `shouldResume`
  - route changes: pause when headphones or Bluetooth disconnect
  - media services reset: rebuild the engine
- **Now Playing / remote commands**: play/pause/toggle, skip ±N (uses the user's intervals), change playback position (scrubbing from the lock screen), next/previous track mapped to **chapter** navigation, playback rate. Now Playing shows the chapter title, with book title and author as the subtitle. Elapsed time is either per chapter or per book (a setting).
- **iCloud audio**: before loading a file the engine asks for a local copy (`startDownloadingUbiquitousItem`) and waits for it; the next file is fetched ahead.
- **Persistence of position**: saved every 5 s while playing, plus on pause, scene background, interruption and termination. Each save writes `(bookID, globalPosition, updatedAt)`.
- **Smart rewind**: after resuming, rewind by 0 s (pause < 1 min), 5 s (< 10 min), 15 s (< 1 h) or 30 s (≥ 1 h). Configurable.

---

## 5. Feature list

### Library and import
- Import from the Files app: a document picker for files **and folders**. Everything is **copied** into `<library>/<bookID>/`, with security-scoped access held only for the duration of the copy. `<library>` is `Library/` in the app's iCloud Drive container when iCloud is available, else `Application Support/Library/`
- "Open in…" / share sheet, AirDrop, and Finder file sharing (`UIFileSharingEnabled`, `LSSupportsOpeningDocumentsInPlace`). A watched `Documents/Inbox` folder is auto-imported.
- Zip import
- Background import queue with progress. Durations are probed lazily, so a large library imports quickly.
- Library views: **Titles / Authors / Series / Narrators / Collections** tabs (like Audible), grid ↔ list, sort (recent, title, author, progress, date added), filters (not started / in progress / finished / downloaded), search
- User collections (playlists of books), mark as finished/unfinished, reset progress
- Remove download (evict the local copy; it stays in iCloud and downloads again on play) or delete a book everywhere; storage usage screen

### Player
- Mini player in the tab bar's bottom accessory (`tabViewBottomAccessory`), which shrinks inline when the tab bar minimizes on scroll. Tapping it opens the full player with a zoom navigation transition.
- Full player:
  - large cover; book title; current chapter
  - scrubber in **chapter** or **whole-book** mode (tap to toggle)
  - elapsed / remaining time, plus "Xh Ym left" adjusted for speed
- Skip back/forward with configurable intervals (5/10/15/30/45/60/90 s)
- Speed 0.5×–3.5× with a fine-step picker and presets. Speed is remembered per book, with a global default.
- **Sleep timer**: 5–120 min, end of chapter, or custom. Volume fades out over the last 10 s, and a **shake extends** the timer. The timer can turn on automatically during set night hours.
- Chapter list with progress, current-chapter highlight and tap-to-jump. Next/previous chapter buttons.
- **Bookmarks** with optional notes and a list per book, plus "add bookmark" from the lock screen and headphones (configurable)
- AirPlay route picker, smart rewind, auto-play next book in series (optional)

### System integration
- Lock screen / Control Center / Dynamic Island Now Playing
- **CarPlay** audio app (needs the `com.apple.developer.carplay-audio` entitlement, requested from Apple): Continue Listening, Library, chapters
- **Widgets**: Home and Lock Screen "Continue Listening" with an interactive play/pause (App Intents)
- **App Intents / Siri / Shortcuts**: "Resume my audiobook", "Play \<title\>", "Set sleep timer", "Skip back"
- iCloud sync of the whole library: SwiftData + CloudKit for records, iCloud Drive for audio. Audio downloads on demand, so a second device only stores what it plays. Signing in later moves a local library into iCloud; signed out, everything stays local
- *Later:* Apple Watch remote, Live Activity

### Stats and polish
- Listening time per day/week, streaks, finished books, time saved by listening at faster speeds
- Accessibility: VoiceOver labels on every control, Dynamic Type up to AX5, Reduce Motion support, 44 pt hit targets
- Localization-ready (String Catalogs)
- Haptics on skip, bookmark and sleep-timer events

---

## 6. Interface design (Audible layout, Liquid Glass materials)

### Liquid Glass principles
- **Two layers.** Content (covers, lists, text) sits on a solid cool grey or white layer. Navigation and controls float above it in **glass**. Glass is never stacked on glass and never used for content cards.
- **Let the system do it first.** Tab bars, toolbars, sheets, menus, search fields and the tab bar's bottom accessory get Liquid Glass automatically on iOS 26. Custom glass is limited to the player controls and a few floating buttons.
- **Custom glass APIs:** `.glassEffect(.regular.tint(Theme.primary).interactive(), in: .circle)` for the play button; `.buttonStyle(.glass)` / `.glassProminent` for secondary/primary actions; `GlassEffectContainer` + `glassEffectID` so the player's control cluster morphs as a group (e.g. the sleep timer pill expanding into a countdown).
- **Navy as tint, not fill.** Navy appears as the tint of prominent glass (play button, primary actions) and as the app's `.tint`. Large flat navy areas are avoided because they fight the glass.
- **Edge-to-edge artwork.** Book detail and the full player use `.backgroundExtensionEffect()` so cover art extends softly under the glass toolbar and sidebar edges.
- **Accessibility.** Test with Reduce Transparency (glass falls back to frosted solid), Increase Contrast and Reduce Motion (no morphing), all handled by system glass if we don't fake it with custom blurs.

### Navigation
`TabView` with **Home · Library · Stats · Settings** plus a `Tab(role: .search)` search tab, which iOS 26 renders as a separate glass button.

- `.tabBarMinimizeBehavior(.onScrollDown)` collapses the tab bar while browsing.
- The **mini player lives in `.tabViewBottomAccessory`**: cover thumbnail, title/chapter, play/pause and skip. It reads `@Environment(\.tabViewBottomAccessoryPlacement)` to show a compact layout when the tab bar is minimized.
- Tapping the mini player presents the full player with `.navigationTransition(.zoom(sourceID:in:))` from the accessory.

### Screens
- **Home**: a large "Continue Listening" hero card (cover, progress bar, glass play button), then horizontal rows: *Recently added*, *In progress*, *Next in series*, *Finished recently*. Glass toolbar with an Import (`+`) button.
- **Library**: a segmented picker in the glass toolbar (Titles · Authors · Series · Narrators · Collections), cover rows with title, author, narrator, a thin progress bar and "3h 12m left". Sort/filter in a toolbar menu.
- **Book detail**: cover artwork extended behind the toolbar, metadata, description, chapter list, files, edit metadata. A floating `.glassProminent` "Play / Resume" button.
- **Full player**: a cover-dominant layout over a blurred, colour-sampled cover backdrop. A `GlassEffectContainer` holds the transport: skip back, a large navy-tinted glass play button, and skip forward. The bottom glass toolbar has **Speed · Sleep · Chapters · Bookmark · AirPlay**. Chapters, speed and sleep open as sheets with partial detents, which are glass by default.

### Color tokens (Assets.xcassets color sets, exposed through `Theme`)

| Token | Light | Dark |
|---|---|---|
| `primary` (dark blue; app `.tint` and glass tint) | `#14295A` | `#7A9CE8` (lifted so it has enough contrast on dark) |
| `primaryPressed` | `#0D1C40` | `#5F84D9` |
| `onPrimary` | `#FFFFFF` | `#0B1220` |
| `accent` (progress, links) | `#2F62D8` | `#8FB0FF` |
| `background` (cool grey) | `#EEF1F5` | `#0F1318` |
| `surface` (cards) | `#FFFFFF` | `#181D24` |
| `surfaceSecondary` | `#E2E6EC` | `#222831` |
| `textPrimary` | `#111827` | `#EEF1F5` |
| `textSecondary` | `#5A6472` | `#9AA4B2` |
| `separator` | `#D3D9E1` | `#2C333D` |
| `success` (finished) | `#1F8A5B` | `#4CC38A` |

All text/background pairs are checked against WCAG AA in a unit test that loads the color sets.

### Typography and components
- SF Pro with Dynamic Type styles. Titles are `.title2.bold()`; metadata is `.subheadline` in `textSecondary`.
- Covers: 8 pt corner radius and a subtle shadow on light backgrounds. A square placeholder generated from the title and a hashed navy gradient.
- Components: `CoverView`, `BookRow`, `BookCard`, `ProgressBar`, `GlassPlayButton`, `TransportCluster`, `MiniPlayerAccessory`, `ChapterRow`, `SectionHeader`. Each has a snapshot test in light and dark, and with Reduce Transparency on.

---

## 7. Testing strategy

| Layer | What | How / where |
|---|---|---|
| Parsers | MP4 boxes (incl. `chpl`, `covr`, freeform atoms), ID3v2.3/2.4 (CHAP/CTOC, unsynchronisation, extended headers, UTF-16), Vorbis comments, CUE, OverDrive markers, malformed or truncated input never crashing | `swift test` in `Packages/MediaParsing` against `Tests/Fixtures` plus hand-crafted byte buffers |
| Core logic | `BookTimeline` locate/global round-trips (property-style), chapter normalization, grouping heuristics (table-driven: file trees → expected books), metadata precedence, smart-rewind table, sleep-timer state machine | `swift test` in `AudiobookCore`, `Playback` (with a fake clock) |
| Engine integration | Real `AVPlayerEngine` on the simulator: load an m4b and seek to chapter 3; play a 3-file MP3 book and seek across a file boundary; rate change; resume position | XCTest in the app test target |
| Library | Import of each fixture type, zip import, re-scan keeps overrides, SwiftData in-memory store | XCTest |
| UI snapshots | Home, Library, Player, Chapters, Sleep sheet in light/dark, at default and AX3 Dynamic Type, and with Reduce Transparency | swift-snapshot-testing (recorded on the CI simulator model) |
| UI flows | Seeded library via the `-UITestSeedLibrary` launch argument: open a book, play/pause, jump to a chapter, add a bookmark, set the sleep timer, change speed | XCUITest |

**Fixtures** come from `scripts/make-fixtures.sh` (ffmpeg, a sine/silence source at low bitrate, a few seconds each), and the output is committed:
- `chapters.m4b` (QuickTime chapters), `nero-chapters.m4b` (`chpl` only, written by a small post-processing step), `both-chapters.m4b` (chapter track and `chpl`), `chapters.mp3` (ID3 CHAP), `chapters.flac` (Vorbis chapters), `multi-mp3/` (3 tracks + `cover.jpg`), `multi-disc/CD1,CD2/`, `book.mp3 + book.cue`, `overdrive.mp3`, `vbr.mp3`, `corrupt.m4b`, `book.zip`

Coverage target: ≥ 90% for `MediaParsing`/`AudiobookCore`, ≥ 60% overall.

---

## 8. CI — `.github/workflows/ci.yml`

Runs on `pull_request` and pushes to `master`. `concurrency: ci-${{ github.ref }}` with `cancel-in-progress: true`.

```yaml
jobs:
  lint:            # macos-latest
    - brew install swiftlint swiftformat
    - swiftformat --lint . && swiftlint --strict

  package-tests:   # macos-latest, matrix over Packages/*
    - sudo xcode-select -s /Applications/Xcode_26.<pinned>.app   # iOS 26 SDK needs Xcode 26 (macos-26 runner image)
    - swift test --package-path Packages/${{ matrix.pkg }} --enable-code-coverage
    # MediaParsing & AudiobookCore are Foundation-only → also run on ubuntu-latest (cheap, fast)

  app-tests:       # macos-latest
    - cache: ~/Library/Developer/Xcode/DerivedData/**/SourcePackages, keyed on Package.resolved
    - brew install xcodegen && xcodegen generate
    - xcodebuild test
        -scheme EarReader
        -destination 'platform=iOS Simulator,name=<pinned iPhone>,OS=<pinned>'
        -testPlan CI
        -resultBundlePath TestResults.xcresult
        CODE_SIGNING_ALLOWED=NO
    - upload-artifact: TestResults.xcresult (always), snapshot failure diffs
```

- The Xcode version and simulator are pinned in one place (`.xcode-version`, plus an env var in the workflow) so snapshots stay deterministic.
- Branch protection on `master` requires `lint`, `package-tests` and `app-tests`.
- Optional: a PR comment with a coverage summary via `xcrun xccov`.

---

## 9. Manual release — `.github/workflows/release.yml`

Triggered **only by `workflow_dispatch`**:

```yaml
on:
  workflow_dispatch:
    inputs:
      version:      { description: "Marketing version (e.g. 1.3.0)", required: true }
      destination:  { type: choice, options: [testflight, app-store-review], default: testflight }
      release_notes:{ description: "What's new (TestFlight/App Store + GitHub Release)", required: true }
jobs:
  test:      # reuses ci.yml via workflow_call — never ship red
  release:
    needs: test
    environment: production        # required reviewer = manual approval gate
    runs-on: macos-latest
    steps:
      - checkout (fetch-depth: 0); select pinned Xcode; xcodegen generate
      - validate version is semver and > last tag
      - bundle exec fastlane release version:${{ inputs.version }} destination:${{ inputs.destination }}
          # Fastfile lane:
          #  app_store_connect_api_key(key_id, issuer_id, key_content)
          #  setup_ci                                   # temp keychain
          #  match(type: "appstore", readonly: true)    # certs/profiles from private repo
          #  increment_version_number(version)          # MARKETING_VERSION
          #  build number = latest_testflight_build_number + 1
          #  build_app(scheme: "EarReader", export_method: "app-store")
          #  upload_to_testflight(changelog: notes)  | or deliver(submit_for_review: true)
      - git tag v${{ inputs.version }} && git push --tags
      - softprops/action-gh-release: tag, notes, attach dSYMs zip
```

**Secrets** (stored in the `production` environment): `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8_BASE64`, `MATCH_PASSWORD`, `MATCH_GIT_URL`, `MATCH_DEPLOY_KEY` (SSH key for the private certs repo).
*Alternative without match:* `BUILD_CERT_P12_BASE64`, `P12_PASSWORD`, `PROVISIONING_PROFILE_BASE64`, `KEYCHAIN_PASSWORD`, imported with `security` commands.

Optional extra input `sideload: true` to also export an unsigned/ad-hoc IPA as a release asset for AltStore-style installs.

---

## 10. Milestones

The task-level breakdown is in [ROADMAP.md](ROADMAP.md).

| # | Milestone | TestFlight |
|---|---|---|
| M0 | Scaffold: XcodeGen project, packages, theme, Liquid Glass tab shell, CI green | — |
| M1 | TestFlight pipeline: fastlane match, `release.yml`, empty app shipped | 0.1.0 |
| M2 | Media parsing (can run in parallel with M1) | — |
| M3 | Library and import | 0.2.0 |
| M4 | Playback core, mini and full player | 0.3.0 |
| M5 | Player and listening features, Home, Stats | 0.4.0 |
| M6 | System integration: App Intents, widgets, Control Center, CarPlay, iCloud | 0.5.0 |
| M7 | Library power tools | — |
| M8 | Polish and App Store | **1.0.0** |

---

## 11. Risks and mitigations

| Risk | Mitigation |
|---|---|
| AVFoundation misses Nero/ID3 chapters | Our own parsers (M1) with fixtures that cover each variant |
| Inaccurate VBR MP3 seeking | Precise-timing asset option; Xing TOC; test with `vbr.mp3` |
| Gaps between files in multi-MP3 books | `AVQueuePlayer` preroll; an integration test measures the boundary |
| Slow import of large libraries (1000s of files) | Lazy duration probing, batched SwiftData writes, background `ModelActor` |
| CarPlay entitlement approval delay | Request early (during M3); the feature is behind a build flag |
| Snapshot flakiness across Xcode versions | Pinned Xcode + simulator, snapshots recorded only in CI (a `record` workflow input) |
| Storage use from copying large libraries | Storage screen, remove download (evict local audio), warn before importing more than the free space |
| Audiobooks fill the user's iCloud storage (0.5–1 GB each) | Show iCloud usage on the storage screen; a clear error when iCloud is full, with the book kept locally |
| Audio not downloaded yet on this device | Download state on every book; playback waits for (and shows) the download; prefetch the next file of the current book |
| Glass rendering differs between simulator runs, which makes snapshots flaky | Snapshot tests use a small per-pixel tolerance; glass-heavy screens are also snapshotted with Reduce Transparency, which renders deterministically |
| Signing breakage in CI | fastlane match readonly + App Store Connect API key, never Apple ID passwords |

---

## 12. Resolved questions

All original open questions are resolved; see **Decisions** at the top.
