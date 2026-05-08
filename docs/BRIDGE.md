# Bridge (Swift ↔ Obj-C++ ↔ C++)

The bridge is a thin extern "C" facade exposed to Swift via the bridging
header, implemented in Objective-C++ that calls into the desktop's C++
core. Nothing above the bridge knows about JUCE; nothing below it knows
about Swift / UIKit / SwiftUI.

## Bridge ABI
`StylusBridge.h` is a plain-C header used as the Swift-Objective-C bridging
header (`SWIFT_OBJC_BRIDGING_HEADER` in [project.yml](../project.yml)). All
`Stylus_*` symbols and `StylusTrackC` are visible to Swift directly without
`import StylusBridge` or a modulemap.

The library handle is an opaque pointer:
```c
typedef struct StylusLibrary StylusLibrary;
typedef StylusLibrary* StylusLibraryHandle;
```
which Swift imports as `OpaquePointer`. The full struct definition lives in
the .mm at namespace scope so the tag matches across the C / C++ boundary.
Callbacks pass `void* userData`, which Swift fills with
`Unmanaged<LibraryStore>.passUnretained(self).toOpaque()` so the C function
can recover the Swift instance.

`StylusTrackC.const char*` fields point to UTF-8 storage owned by a local
`TrackBytes` instance for the duration of the callback. Callers must copy
what they keep; the strings die when the callback returns.

## JUCE INTERFACE-link gotcha
JUCE 8's `juce_add_module` attaches sources via INTERFACE properties, so
every consumer that links a JUCE module compiles its own copy. If
`StylusBridge` were its own static lib that linked `juce::juce_*`, the app
would see duplicate symbols at link time. Solution: the bridge .mm is
compiled into the same `StylusCore` target as the rest of the C++ core, so
there's exactly one set of JUCE objects in the output `libStylusCore.a`.
Do not split it into a second static lib.

## JUCE message thread on iOS
`Stylus_Initialize()` calls `juce::initialiseJuce_GUI()` once from the main
thread (lazy via `std::call_once`). That installs JUCE's CFRunLoopSource
on the main run loop so `juce::MessageManager::callAsync(...)` from JUCE's
background scanner thread is delivered as a main-thread tick to our
callbacks. Always call `Stylus_Initialize()` from the SwiftUI App's `init`
or before any other `Stylus_*` call.

## Adding a new bridge function checklist
1. Add the C declaration to [Sources/StylusBridge/StylusBridge.h](../Sources/StylusBridge/StylusBridge.h)
   inside `extern "C"`. Use `int32_t` / `int64_t` over `int` / `long` for
   ABI stability across Swift / Obj-C bridging.
2. Implement in [Sources/StylusBridge/StylusBridge.mm](../Sources/StylusBridge/StylusBridge.mm).
   Marshal `juce::String` via `toStdString()` into a TrackBytes-equivalent
   owner struct so the `const char*` fields outlive the callback.
3. If the function is called from a callback that must run on the main
   thread, wrap your dispatch in `juce::MessageManager::callAsync`.
4. Add the Swift call site in [Sources/StylusApp/Library/LibraryStore.swift](../Sources/StylusApp/Library/LibraryStore.swift)
   (or wherever fits). Bridge `void* userData` via
   `Unmanaged.passUnretained(self).toOpaque()`.
5. No `make regen` is needed for header / .mm changes; just build.
