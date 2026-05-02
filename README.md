# Stylus iOS

iOS / iPad port of [Stylus](https://github.com/greghcarr/stylus), a C++17/JUCE audio player. Hybrid architecture: SwiftUI app shell over a C++ static library (`StylusCore`) that reuses the desktop project's analysis, library scanner, `.styl` sidecar I/O, and Apple Music lookup verbatim.

See [IOS_PORT_PLAN.md](External/stylus/IOS_PORT_PLAN.md) in the desktop submodule for the full architecture and phased delivery plan.

## Repo layout

```
stylus-ios/
  CMakeLists.txt        verifies StylusCore compiles for iOS
  External/
    stylus/             git submodule -> github.com/greghcarr/stylus
                        all C++ core sources live here, vendored verbatim
  Sources/              (planned, post-Phase 1)
    StylusBridge/       Objective-C++ bridge: Swift-callable C facade
    StylusApp/          SwiftUI app
  StylusApp.xcodeproj/  (planned, post-Phase 1) iOS app project
```

## Submodule operations

This project pulls the Stylus C++ core in as a git submodule under `External/stylus`. A submodule is a pinned reference to a specific commit in another repo; cloning this repo does not automatically pull the submodule contents.

**Cloning fresh (anyone, including you on a new machine):**

```sh
git clone --recurse-submodules https://github.com/greghcarr/stylus-ios.git
```

If you cloned without `--recurse-submodules`, run this once inside the repo:

```sh
git submodule update --init --recursive
```

**After someone else pushes desktop-Stylus changes that this repo should pick up:**

```sh
git submodule update --remote External/stylus
git add External/stylus
git commit -m "Bump stylus submodule to <reason>"
```

The submodule does not auto-update. The `--remote` flag pulls the latest commit from the submodule's tracked branch (`master`) and updates the working tree. The `git add` then records the new pinned commit in this repo. Until that commit is made and pushed, the submodule stays at whatever commit was last pinned.

**To check what commit the submodule is currently pinned to:**

```sh
git submodule status
```

A `+` prefix means the submodule has uncommitted changes vs. the pin; a `-` means it's not yet initialized.

## Phase 0: verify StylusCore builds for iOS

Phase 0 is desktop-side and already shipped (commit `e0a4e82` in the stylus repo): the analysis / library / `.styl` layer was extracted into a `StylusCore` CMake target with no juce_graphics or juce_gui_basics dependency.

This iOS repo's first job is to confirm that same library compiles cleanly for the iOS toolchain.

**iOS Simulator (arm64, recommended for development):**

```sh
cmake -B build-ios-sim -G Xcode \
      -DCMAKE_SYSTEM_NAME=iOS \
      -DCMAKE_OSX_SYSROOT=iphonesimulator \
      -DCMAKE_OSX_DEPLOYMENT_TARGET=16.0 \
      -DCMAKE_OSX_ARCHITECTURES=arm64
cmake --build build-ios-sim --config Debug
```

Output: `build-ios-sim/Debug-iphonesimulator/libStylusCore.a`

**iOS Device:**

```sh
cmake -B build-ios-device -G Xcode \
      -DCMAKE_SYSTEM_NAME=iOS \
      -DCMAKE_OSX_SYSROOT=iphoneos \
      -DCMAKE_OSX_DEPLOYMENT_TARGET=16.0 \
      -DCMAKE_OSX_ARCHITECTURES=arm64
cmake --build build-ios-device --config Debug
```

The first configure pulls JUCE 8.0.4 via FetchContent (a few minutes). Subsequent configures reuse the cache.

## Roadmap

- [x] **Phase 0** Desktop core extraction (in stylus repo, commit `e0a4e82`)
- [ ] **Phase 1** Bridge `Stylus_LibraryCreate` + `Stylus_LibraryStartScan` + `Stylus_StylLoad`; SwiftUI `List` view; tap-to-play with `AVAudioPlayer`
- [ ] **Phase 2** Full `.styl` metadata + album art
- [ ] **Phase 3** Transport, queue, Now Playing, lock screen
- [ ] **Phase 4** Sidebar views (Artists / Albums / Playlists / Search)
- [ ] **Phase 5** Background analysis (BPM / key)
- [ ] **Phase 6** Apple Music lookup
- [ ] **Phase 7** Drag-and-drop playlist editing
- [ ] **Phase 8** iPad NavigationSplitView, AirPlay, polish
- [ ] **Phase 9** (desktop side) Cable + Wi-Fi sync engine via libimobiledevice

Full plan: [IOS_PORT_PLAN.md](External/stylus/IOS_PORT_PLAN.md).
