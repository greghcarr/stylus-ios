cmake_minimum_required(VERSION 3.22)
project(StylusIOS VERSION 0.1.0 LANGUAGES CXX OBJCXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Configure for iOS unless the caller explicitly requests another platform.
# Build for the simulator with:
#   cmake -B build-ios-sim -G Xcode \
#         -DCMAKE_SYSTEM_NAME=iOS \
#         -DCMAKE_OSX_SYSROOT=iphonesimulator \
#         -DCMAKE_OSX_DEPLOYMENT_TARGET=16.0 \
#         -DCMAKE_OSX_ARCHITECTURES=arm64
#   cmake --build build-ios-sim --config Debug
#
# Build for a real device with:
#   cmake -B build-ios-device -G Xcode \
#         -DCMAKE_SYSTEM_NAME=iOS \
#         -DCMAKE_OSX_SYSROOT=iphoneos \
#         -DCMAKE_OSX_DEPLOYMENT_TARGET=16.0 \
#         -DCMAKE_OSX_ARCHITECTURES=arm64

include(FetchContent)

FetchContent_Declare(
    JUCE
    GIT_REPOSITORY https://github.com/juce-framework/JUCE.git
    GIT_TAG        8.0.4
    GIT_SHALLOW    TRUE
)
FetchContent_MakeAvailable(JUCE)

set(STYLUS_DIR "${CMAKE_SOURCE_DIR}/External/stylus")

# StylusCore: same library as the desktop project, built for iOS.
# Source list mirrors the desktop CMakeLists' StylusCore target. AlbumArtExtractor
# ships only as the .mm file; the juce::Image-returning .cpp wrapper stays in
# the desktop GUI target since juce::Image lives in juce_graphics.
add_library(StylusCore STATIC
    ${STYLUS_DIR}/src/audio/PlayQueue.cpp
    ${STYLUS_DIR}/src/audio/StylFile.cpp
    ${STYLUS_DIR}/src/audio/AlbumArtExtractor.mm
    ${STYLUS_DIR}/src/analysis/BpmDetector.cpp
    ${STYLUS_DIR}/src/analysis/KeyDetector.cpp
    ${STYLUS_DIR}/src/analysis/AnalysisEngine.cpp
    ${STYLUS_DIR}/src/analysis/AppleMusicLookup.cpp
    ${STYLUS_DIR}/src/library/LibraryScanner.cpp
    ${STYLUS_DIR}/src/library/LibraryCache.cpp
    ${STYLUS_DIR}/src/library/PlaylistStore.cpp
)

target_include_directories(StylusCore PUBLIC ${STYLUS_DIR}/src)

target_link_libraries(StylusCore
    PUBLIC
        juce::juce_core
        juce::juce_data_structures
        juce::juce_audio_basics
        juce::juce_audio_formats
        juce::juce_dsp
        juce::juce_recommended_config_flags
        juce::juce_recommended_warning_flags
)

target_compile_definitions(StylusCore PRIVATE
    JUCE_USE_CURL=0
    JUCE_USE_MIDI_INPUTS=0
    JUCE_USE_MIDI_OUTPUTS=0
    JUCE_WEB_BROWSER=0
)
