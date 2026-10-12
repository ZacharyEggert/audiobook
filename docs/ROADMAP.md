# Ear Reader — Roadmap

This roadmap breaks [PLAN.md](PLAN.md) into milestones and PR-sized tasks. Each task is meant to be one PR that keeps CI green.

**Legend**
- 👤 = only you can do this (Apple accounts, secrets, approvals)
- 🧪 = the PR must add or extend tests
- *Learn:* Swift / iOS concepts the milestone introduces, as pointers for picking up native iOS

**Target:** v1.0 on the App Store after M8. TestFlight builds are available from M1 onward, so every later milestone can be tried on a real device.

```
M0 Scaffold ─► M1 TestFlight pipeline ─► M2 Parsing ─► M3 Library & import ─► M4 Playback core
                                                                                    │
            M8 Polish & App Store ◄─ M7 Library tools ◄─ M6 System integration ◄─ M5 Player & listening features
```

M2 (parsing) is pure Swift and can be built in parallel with M1.

---

## M0 — Scaffold

**Goal:** an empty Ear Reader app with the Liquid Glass tab shell builds and tests in CI.

| # | Task | Done when |
|---|---|---|
| 0.1 | `Brewfile` (xcodegen, swiftlint, swiftformat, ffmpeg), `scripts/bootstrap.sh`, `.xcode-version`, `.gitignore` additions (`*.xcodeproj`) | `./scripts/bootstrap.sh` on a fresh Mac produces an openable project |
| 0.2 | `project.yml`: `EarReader` app target, bundle ID `llc.ex-nihilo.audiobook`, iOS 26 deployment target, Swift 6.2, background audio mode, App Group, `UIFileSharingEnabled`, `LSSupportsOpeningDocumentsInPlace` = NO (we copy files in), document types for audio/zip | Builds in the simulator |
| 0.3 | Empty local packages `MediaParsing`, `AudiobookCore`, `Playback`, `Library`, each with one placeholder Swift Testing test 🧪 | `swift test` passes in each |
| 0.4 | `DesignSystem`: color sets from PLAN §6, `Theme`, app `.tint(Theme.primary)`, WCAG contrast test 🧪 | Contrast test passes for every text/background pair |
| 0.5 | Tab shell: Home · Library · Stats · Settings + search tab, `.tabBarMinimizeBehavior(.onScrollDown)`, placeholder `tabViewBottomAccessory` mini player | Matches the navigation spec visually |
| 0.6 | SwiftLint + SwiftFormat configs; `.github/workflows/ci.yml` (lint, package-tests, app-tests, xcresult upload) | CI is green on a PR |
| 0.7 | 👤 Turn on branch protection for `master` requiring the three CI jobs | Direct pushes to `master` are blocked |
| 0.8 | `CLAUDE.md` / `CONTRIBUTING.md`: how to bootstrap, run tests and regenerate the project | — |

*Learn:* Xcode project anatomy, SwiftUI `App`/`Scene`, `TabView`, asset catalogs, Swift Package Manager, Swift Testing (`@Test`, `#expect`).

---

## M1 — TestFlight pipeline

**Goal:** press a button in GitHub Actions and the empty app arrives in TestFlight. This removes the signing risk early.

| # | Task | Done when |
|---|---|---|
| 1.1 | 👤 In the Apple Developer portal, register the App ID `llc.ex-nihilo.audiobook` (Background Modes, App Groups, iCloud/CloudKit) and the App Group `group.llc.ex-nihilo.audiobook` | IDs exist |
| 1.2 | 👤 In App Store Connect, create the app record "Ear Reader" and an **App Store Connect API key** (App Manager role) | Key ID, Issuer ID and `.p8` in hand |
| 1.3 | 👤 Create a private repo for fastlane match certificates, plus a deploy key | Repo exists |
| 1.4 | fastlane setup: `Gemfile`, `Appfile`, `Matchfile`, a `Fastfile` with `certificates` (run once locally to create certs) and `release` lanes | `bundle exec fastlane release` works locally |
| 1.5 | `.github/workflows/release.yml`: `workflow_dispatch` inputs (version, destination, notes), reuse of CI via `workflow_call`, `production` environment, tag + GitHub Release with dSYMs | — |
| 1.6 | 👤 Add the secrets to the `production` environment (`ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8_BASE64`, `MATCH_PASSWORD`, `MATCH_GIT_URL`, `MATCH_DEPLOY_KEY`) and yourself as required reviewer | — |
| 1.7 | Placeholder app icon and launch screen | — |
| 1.8 | First dispatch: **0.1.0 → TestFlight** | The build installs on your phone through TestFlight |

*Learn:* code signing (certificates, provisioning profiles), App Store Connect, build vs marketing version numbers.

---

## M2 — Media parsing

**Goal:** given any supported file, return metadata, cover and chapters. Everything here is pure Swift and unit-tested; no UI.

| # | Task | Done when |
|---|---|---|
| 2.1 | `scripts/make-fixtures.sh` + committed fixtures (PLAN §7 list), all < 2 MB total | Script is reproducible |
| 2.2 | Binary reader utilities (`ByteReader`: big/little endian, syncsafe ints, bounded slices that never trap) 🧪 | Fuzz-style tests on truncated input |
| 2.3 | MP4 box walker: `moov/udta/meta/ilst` metadata, `covr`, freeform `----` atoms, `chpl` Nero chapters 🧪 | `chapters.m4b`, `nero-chapters.m4b` parse correctly |
| 2.4 | QuickTime chapter track reading via `AVAsset.loadChapterMetadataGroups` (in `Library`, since it needs AVFoundation) 🧪 | Chapter titles and times match the fixture |
| 2.5 | ID3v2.3/2.4: text frames, `TXXX`, `COMM`, `APIC`, `CHAP`/`CTOC`, unsynchronisation, UTF-16 🧪 | `chapters.mp3` and `overdrive.mp3` parse correctly |
| 2.6 | MP3 duration: Xing/Info/VBRI headers, plus a CBR fallback 🧪 | `vbr.mp3` duration within 0.5 s |
| 2.7 | FLAC metadata blocks + Vorbis comments (`CHAPTERxxx`, `METADATA_BLOCK_PICTURE`) 🧪 | `chapters.flac` parses correctly |
| 2.8 | CUE sheet parser 🧪 | `book.cue` gives the right chapters |
| 2.9 | Unified `MediaProbe.probe(url) -> ProbeResult` using the chapter resolution order (PLAN §3.2) and metadata mapping (PLAN §3.3) 🧪 | Table-driven test over every fixture |
| 2.10 | Unsupported detection (`.aax`, `.aaxc`, `.ogg`, `.opus`, `.wma`) with a clear reason 🧪 | — |

*Learn:* `Data` and byte manipulation, value types, `throws` and typed errors, `Sendable`.

---

## M3 — Library and import

**Goal:** import files and folders and see correct books in the Library.

| # | Task | Done when |
|---|---|---|
| 3.1 | `AudiobookCore` models (`Book`, `AudioFile`, `Chapter`) and `BookTimeline` 🧪 | Round-trip property tests |
| 3.2 | Grouping heuristics: single file, folder, multi-disc, folder of m4bs, natural sort 🧪 | Table-driven tests of file trees → books |
| 3.3 | SwiftData schema (`BookRecord`, `FileRecord`, `ChapterRecord`, `ProgressRecord`, `BookmarkRecord`, `CollectionRecord`, `MetadataOverride`) with a `VersionedSchema` from day one | In-memory store tests 🧪 |
| 3.4 | Import pipeline on a `@ModelActor`: copy into `Application Support/Library/<bookID>/`, probe, group, persist, report progress; cleans up on failure 🧪 | Importing each fixture gives the expected book |
| 3.5 | Entry points: `.fileImporter` (files and folders, multiple), "Open in…" / share sheet, Finder file sharing via `Documents/Inbox` scan at launch and on foreground | Each path imports |
| 3.6 | Zip import via ZIPFoundation 🧪 | `book.zip` imports |
| 3.7 | Cover pipeline: extract, downscale to 3 sizes, disk cache, generated placeholder | — |
| 3.8 | Library screen: Titles tab (grid/list), sort & filter menu, empty state with an Import button | — |
| 3.9 | Authors / Series / Narrators / Collections tabs | — |
| 3.10 | Book detail screen (backdrop extension, metadata, chapters, files) | — |
| 3.11 | Import progress UI (toolbar progress + a list of failures with reasons) | — |
| 3.12 | Storage screen in Settings, plus delete book / delete audio but keep progress | — |

*Learn:* SwiftData (`@Model`, `@Query`, `ModelActor`), Swift concurrency (`async`/`await`, actors, `TaskGroup`), the file system sandbox, security-scoped URLs.

**Release:** 0.2.0 to TestFlight (an import-only build that's still useful for testing real libraries).

---

## M4 — Playback core

**Goal:** books play reliably in the background with lock-screen control and resume exactly where you left off.

| # | Task | Done when |
|---|---|---|
| 4.1 | `PlaybackEngine` protocol + `FakeEngine` for tests | — |
| 4.2 | `AVPlayerEngine`: queue from the current file, global-time seeking, preroll, rate with `.timeDomain` pitch 🧪 | Simulator integration tests: seek across a file boundary, m4b chapter seek |
| 4.3 | `PlayerController` (`@Observable`, main actor): load/play/pause/seek, chapter tracking, events → UI 🧪 | Unit tests with `FakeEngine` |
| 4.4 | Audio session: `.playback` / `.spokenAudio`, interruptions, route changes, media-services reset 🧪 | Pauses on headphone unplug; resumes after a call |
| 4.5 | Now Playing info + remote commands (play/pause, skip ±N, scrub, next/previous chapter, rate) | Lock screen and AirPods work on device |
| 4.6 | Position persistence (every 5 s plus lifecycle events) and restoring the last book at launch 🧪 | Force-quit and relaunch resumes within 1 s |
| 4.7 | Mini player in `tabViewBottomAccessory` (expanded and inline layouts) | — |
| 4.8 | Full player v1: cover, chapter title, scrubber, transport `GlassEffectContainer`, zoom transition from the mini player | — |
| 4.9 | Chapters sheet: list, current-chapter highlight, tap to jump | — |

*Learn:* AVFoundation (`AVQueuePlayer`, `CMTime`, time observers), the MediaPlayer framework, app lifecycle (`scenePhase`), `matchedTransitionSource` / zoom transitions, Liquid Glass APIs.

**Release:** 0.3.0, the first build that's a usable audiobook player.

---

## M5 — Player and listening features

| # | Task | Done when |
|---|---|---|
| 5.1 | Skip interval settings (separate back/forward), smart rewind table 🧪 | — |
| 5.2 | Speed sheet: 0.5–3.5× fine stepper + presets; per-book memory with a global default | — |
| 5.3 | Sleep timer state machine (duration, end of chapter), fade-out, shake to extend, auto night mode 🧪 | Fake-clock tests |
| 5.4 | Sleep-timer pill morphing in the glass transport (`glassEffectID`) | — |
| 5.5 | Bookmarks: add (button, lock screen, headphones option), notes, list per book, jump 🧪 | — |
| 5.6 | Scrubber modes (chapter / whole book), time remaining adjusted for speed | — |
| 5.7 | Home screen: Continue Listening hero, Recently added / In progress / Next in series / Finished rows | — |
| 5.8 | Mark finished/unfinished, reset progress, auto-play next in series (setting) | — |
| 5.9 | Listening session logging + Stats tab (daily chart, streak, totals, time saved by speed) 🧪 | — |
| 5.10 | Search tab: titles, authors, narrators, series, chapter titles | — |
| 5.11 | Haptics, AirPlay route picker | — |

*Learn:* state machines in Swift, `Timer` vs `Task.sleep`-based clocks, Core Motion (shake), Swift Charts.

**Release:** 0.4.0, feature-complete for daily use.

---

## M6 — System integration

| # | Task | Done when |
|---|---|---|
| 6.1 | 👤 Request the **CarPlay audio entitlement** from Apple (do this at the *start* of M4; approval can take weeks) | Entitlement granted |
| 6.2 | App Intents: Resume, Play book (with `AppEntity` for books), Pause, Skip back, Set sleep timer; Siri phrases; Shortcuts | Works from Siri and Shortcuts |
| 6.3 | Widgets extension: Continue Listening (Home + Lock Screen) with an interactive play/pause intent; shared App Group container for the data | — |
| 6.4 | Control Center control (iOS 26 `ControlWidget`): play/pause current book | — |
| 6.5 | CarPlay scene: Continue Listening, Library list, chapters, Now Playing template | Works in the CarPlay simulator |
| 6.6 | iCloud sync of progress, bookmarks and collections (a separate SwiftData configuration with CloudKit; audio stays local). Conflict rule: the newest `updatedAt` wins for position 🧪 | Progress moves between two devices |

*Learn:* App extensions, App Groups, WidgetKit timelines, App Intents, CloudKit basics.

**Release:** 0.5.0.

---

## M7 — Library power tools

| # | Task | Done when |
|---|---|---|
| 7.1 | Metadata editor (title, authors, narrators, series/index, description, cover from Photos/Files), stored as overrides 🧪 | Survives a re-scan |
| 7.2 | Merge books / split a book by file / reorder files 🧪 | — |
| 7.3 | User collections: create, add/remove, reorder | — |
| 7.4 | Re-scan library and fix missing files | — |
| 7.5 | Import performance pass: 1,000-file library imports in reasonable time, with no UI hitches (Instruments) | — |

---

## M8 — Polish and App Store

| # | Task | Done when |
|---|---|---|
| 8.1 | Accessibility audit: VoiceOver on every screen, Dynamic Type AX5, Reduce Transparency/Motion, Increase Contrast | Checklist complete |
| 8.2 | Snapshot test suite finalized (light/dark, AX3, Reduce Transparency) | — |
| 8.3 | Final app icon (iOS 26 layered icon via Icon Composer: light, dark, tinted, clear) | — |
| 8.4 | Onboarding / empty state that explains how to import | — |
| 8.5 | String Catalog extraction (English only at launch, ready for localization) | — |
| 8.6 | Privacy manifest (`PrivacyInfo.xcprivacy`), App Privacy answers ("Data not collected") | — |
| 8.7 | App Store screenshots via fastlane `snapshot` from UI tests, plus metadata in `fastlane/metadata` | — |
| 8.8 | 👤 Write the App Store description, choose keywords and a support URL, and supply a privacy policy URL | — |
| 8.9 | Dispatch **1.0.0 → app-store-review** | Approved 🎉 |

---

## After v1.0 (out of scope for now)

- Ogg/Opus playback via an `AVAudioEngine` decoder engine, which would also allow volume boost, voice EQ and silence trimming
- Audiobookshelf / Plex / WebDAV sources
- Apple Watch remote and offline playback
- Live Activity for the sleep timer
- iPad and Mac (Designed for iPad) layouts with sidebar navigation
