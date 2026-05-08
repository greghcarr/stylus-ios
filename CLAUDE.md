# Stylus iOS: Architecture Reference

SwiftUI + iOS shell over the C++17/JUCE 8.0.4 audio core from the desktop
[Stylus](External/stylus) project, vendored as a git submodule. Architecture
is a thin Objective-C++ bridge that exposes a Swift-callable C facade so the
desktop's library scanner, `.styl` sidecar I/O, BPM / key analysis, and
Apple Music lookup can be reused verbatim. Nothing above the bridge knows
about JUCE; nothing below it knows about Swift / UIKit / SwiftUI.

## How this documentation is organised

This file is the index. Detailed reference lives in [docs/](docs/), split
by topic. Read this CLAUDE.md when you start a session; jump into the
relevant doc file when working on something specific.

- [docs/ROADMAP.md](docs/ROADMAP.md) -- phase-by-phase status. Read first
  to confirm the current state; update when finishing a phase or scoping a
  new one.
- [docs/BUILD.md](docs/BUILD.md) -- `make` targets, deployment target, Xcode
  disk-usage caveats, CMake script-phase tricks, submodule update workflow.
- [docs/FILES.md](docs/FILES.md) -- every Source file annotated with its
  responsibility. Search here first when locating where something lives.
- [docs/BRIDGE.md](docs/BRIDGE.md) -- Swift ↔ Obj-C++ ↔ C++ ABI, JUCE linking
  gotcha, JUCE message-thread setup, checklist for adding a new bridge fn.
- [docs/AUDIO.md](docs/AUDIO.md) -- AVAudioEngine lifecycle, AVAudioSession
  notification handling, MPNowPlayingInfoCenter integration, album art cache
  + extractor lookup chain.
- [docs/LIBRARY.md](docs/LIBRARY.md) -- folder picker + security-scoped
  bookmark, cache-then-scan flow, per-file scanner timeout, scan progress
  bar, skip-scan launch optimisation.
- [docs/UI.md](docs/UI.md) -- NowPlayingSheet's sheetY model, custom
  navigation chrome, TabRouter env-key decision, row Button + contentShape
  pattern, splash / launch storyboard alignment, sheet presentation rules.
  Includes the checklist for adding a new SwiftUI view.

When new architectural notes need to be captured, add them to the relevant
doc file (or create a new topic file under [docs/](docs/) and link it here).
Keep this top-level CLAUDE.md as a brief index, not a dumping ground.

## Conventions
- No em-dashes or en-dashes anywhere (per global CLAUDE.md). Plain hyphens
  for separators.
- `DEVELOPMENT_TEAM` lives in `project.yml` so it survives `xcodegen`
  regenerations. Personal-team Apple ID's team ID is what goes here.
- File references in Markdown use the relative path link form, not backticks.
- Don't add `UIFileSharingEnabled` back to expose Documents in Files unless
  Documents has something useful in it. Currently it's just there as a
  workaround so "On My iPhone" appears as a Files-app surface.
- The CMake target generates the inner `StylusIOS.xcodeproj` but that's a
  build artifact. The user-facing project is `StylusApp.xcodeproj` which is
  XcodeGen-driven.
- Every list-row view (Button, NavigationLink, or any other top-level
  ForEach child) gets `.alignmentGuide(.listRowSeparatorLeading) { _ in 0 }`
  so dividers extend symmetrically. Apply on every row even if it currently
  has no leading icon, so future leading icons don't accidentally shift the
  divider.

## Doc maintenance (mandatory)
Update **the relevant `docs/` file and [README.md](README.md)** whenever a
change touches:

- Build flow, script-phase logic, [project.yml](project.yml),
  [CMakeLists.txt](CMakeLists.txt), or the [Makefile](Makefile)
  → [docs/BUILD.md](docs/BUILD.md).
- The bridge ABI ([Sources/StylusBridge/StylusBridge.h](Sources/StylusBridge/StylusBridge.h))
  or how Swift calls into it → [docs/BRIDGE.md](docs/BRIDGE.md).
- Audio playback / lock-screen / artwork pipeline → [docs/AUDIO.md](docs/AUDIO.md).
- Library scanner / cache / folder picker behaviour → [docs/LIBRARY.md](docs/LIBRARY.md).
- Architecture ownership / threading / state shape (e.g. who owns the
  security scope, who owns the cache, how the scanner is driven) → the
  most-specific doc, usually [docs/LIBRARY.md](docs/LIBRARY.md) or
  [docs/AUDIO.md](docs/AUDIO.md).
- UI navigation, sheet behaviour, row-press conventions → [docs/UI.md](docs/UI.md).
- File responsibilities / new files / renamed files → [docs/FILES.md](docs/FILES.md).
- Conventions affecting cross-cutting behaviour → this CLAUDE.md.
- Roadmap status → [docs/ROADMAP.md](docs/ROADMAP.md) (mark phases done in
  the README too).

Same commit as the change; never a separate "update docs" follow-up.
The bar for inclusion is "future-Greg or future-Claude would have to read
the diff to understand this." If yes, document it.

If a new topic doesn't fit any existing `docs/` file, create a new one
(e.g. `docs/SYNC.md` when Phase 8 lands) and add it to the index above
in the same commit.
