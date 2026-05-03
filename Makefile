# Stylus iOS — command-line convenience targets.
#
# Most day-to-day work goes through Xcode (open StylusApp.xcodeproj, ⌘R).
# These targets are for re-running xcodegen after editing project.yml, and
# for quick command-line verification builds without going through Xcode IDE.

.DEFAULT_GOAL := regen
.PHONY: help regen build build-sim clean

regen:
	@xcodegen generate
	@echo ""
	@echo "  Project regenerated from project.yml."
	@echo "  If Xcode is open: click Revert in the dialog,"
	@echo "  or File -> Revert Project to Saved if no dialog appeared."

build: regen
	xcodebuild -project StylusApp.xcodeproj -target StylusApp \
	           -configuration Debug -sdk iphoneos \
	           ARCHS=arm64 ONLY_ACTIVE_ARCH=NO \
	           CODE_SIGNING_ALLOWED=NO \
	           build

build-sim: regen
	xcodebuild -project StylusApp.xcodeproj -target StylusApp \
	           -configuration Debug -sdk iphonesimulator \
	           ARCHS=arm64 ONLY_ACTIVE_ARCH=NO \
	           CODE_SIGNING_ALLOWED=NO \
	           build

clean:
	rm -rf build build-ios-device build-ios-sim

help:
	@echo "Stylus iOS make targets:"
	@echo ""
	@echo "  make             Same as 'make regen'."
	@echo "  make regen       Regenerate StylusApp.xcodeproj from project.yml."
	@echo "  make build       Regenerate, then verify-build for iOS device (unsigned)."
	@echo "  make build-sim   Regenerate, then verify-build for iOS Simulator."
	@echo "  make clean       Wipe build/ and build-ios-* CMake build trees."
