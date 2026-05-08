# Build & tooling

Day-to-day: open `StylusApp.xcodeproj` in Xcode, ⌘R. The Xcode project itself
is generated from [project.yml](../project.yml) by [XcodeGen](https://github.com/yonaskolb/XcodeGen)
and is gitignored. `make` regenerates it; click Revert in Xcode if it's open.

Deployment target is iOS 18 (used `.onScrollGeometryChange` for the
NowPlayingSheet's collapsing artwork; the GeometryReader +
PreferenceKey workaround that's standard on iOS 16/17 didn't fire
reliably on the simulator). Bumped from 16 in 2026-05.

```bash
make           # regenerate StylusApp.xcodeproj from project.yml
make build     # unsigned verification build for iOS device
make build-sim # unsigned verification build for iOS Simulator
make clean     # wipe build/ + build-ios-* CMake build trees
```

A pre-build script phase inside the Xcode project drives CMake to build
`libStylusCore.a` automatically; the script lives inline in [project.yml](../project.yml).
You don't need to invoke CMake manually.

## Disk usage (watch `~/Library/Developer/Xcode/DeviceLogs`)
Every device debug-connect session pulls crash dumps + console logs into
`~/Library/Developer/Xcode/DeviceLogs/`. On a heavy debugging day this can
balloon past 10 GB on its own and was the dominant cause of a near-out-of-
disk incident in 2026-05. The directory is purely a transient cache --
deleting its contents is safe and Xcode rebuilds it on demand. Periodic
audit + cleanup:

```bash
du -sh ~/Library/Developer/Xcode/DeviceLogs    # eyeball the size
rm -rf ~/Library/Developer/Xcode/DeviceLogs/*  # wipe; Xcode will repopulate
```

Other dev caches that grow silently and are safe to clear when disk is tight:
`~/Library/Developer/Xcode/iOS DeviceSupport`, `DerivedData`, and the
project's own `build/`, `build-ios-sim/`, `build-ios-device/` (regenerated
by `make build` / `make build-sim`).

## CMake script-phase environment
The pre-build script in [project.yml](../project.yml) clears its environment
with `env -i` before invoking CMake. This is necessary because Xcode injects
`SDKROOT=iphoneos26.4`, `SDK_DIR`, `TOOLCHAINS`, etc., which leak into the
recursive `cmake` call JUCE makes to bootstrap `juceaide` for the host. The
host bootstrap needs the macOS SDK; without sanitisation it fails compiler
detection. The script also restores `DEVELOPER_DIR` from `xcode-select -p`
so the tools are still findable.

## CMake script-phase fast path
The same script in [project.yml](../project.yml) does an mtime-based freshness
check before calling CMake: if `libStylusCore.a` exists and no input under
`Sources/StylusBridge/`, `External/stylus/src/`, or `CMakeLists.txt` is
newer than the lib, it `exit 0`s before invoking cmake at all. This drops
a no-op script-phase invocation from ~6 s to ~1.3 s and is the difference
between "5-10 s ⌘R" and "10-20 s ⌘R" for Swift-only iterations.

If you change CMake-side build options (e.g. add a new source to the cmake
target's source list, or change `-DCMAKE_*` flags), `make clean` once to
force the slow path; the fast path doesn't watch project-config files.

## Submodule update workflow
The desktop submodule is pinned to a specific commit. It does not auto-update.
Bump the pin only when iOS work needs new desktop changes:
```sh
cd External/stylus && git pull origin master  # or work directly in submodule
cd ../..
git add External/stylus
git commit -m "Bump stylus submodule: <reason>"
```
Avoid bumping in isolation; bundle the bump with the iOS work that needs it
so regressions are easy to attribute via `git bisect`.
