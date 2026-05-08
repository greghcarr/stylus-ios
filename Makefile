# Stylus iOS — command-line convenience targets.
#
# Most day-to-day work goes through Xcode (open StylusApp.xcodeproj, ⌘R).
# These targets are for re-running xcodegen after editing project.yml, and
# for quick command-line verification builds without going through Xcode IDE.

.DEFAULT_GOAL := regen
.PHONY: help regen build build-sim test clean

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

# Resolve a test destination: prefer the first connected physical
# iPhone (so the developer doesn't have to keep a multi-GB simulator
# runtime installed); fall back to the first available iPhone
# simulator if no phone is connected. Physical-device tests work
# because project.yml sets DEVELOPMENT_TEAM, so auto-signing handles
# the install for both StylusApp and the test bundle.
#
# UUIDs (rather than device names) sidestep simctl's leading-
# whitespace formatting and stay portable across machines.
DEVICE_ID := $(shell xcrun xctrace list devices 2>&1 | \
                     awk '/^== Devices ==/,/^== Devices Offline ==/ { \
                         if ($$0 ~ /iPhone/ && $$0 !~ /Simulator/ && \
                             match($$0, /\([0-9A-Fa-f-]+\)$$/)) { \
                             print substr($$0, RSTART+1, RLENGTH-2); exit \
                         } \
                     }')
SIM_ID := $(shell xcrun simctl list devices available 2>/dev/null | \
                  awk -F '[()]' '/iPhone [0-9]/ { gsub(/^[[:space:]]+|[[:space:]]+$$/, "", $$2); print $$2; exit }')

TEST_ID       := $(or $(DEVICE_ID),$(SIM_ID))
TEST_PLATFORM := $(if $(DEVICE_ID),iOS,iOS Simulator)

test: regen
	@if [ -z "$(TEST_ID)" ]; then \
	  echo "error: no iPhone (physical or simulator) found - connect a phone via USB or install a simulator" >&2; \
	  exit 1; \
	fi
	@echo "Running tests on $(TEST_PLATFORM) ($(TEST_ID))..."
	xcodebuild -project StylusApp.xcodeproj -scheme StylusAppTests \
	           -destination 'platform=$(TEST_PLATFORM),id=$(TEST_ID)' \
	           -configuration Debug \
	           test

clean:
	rm -rf build build-ios-device build-ios-sim

help:
	@echo "Stylus iOS make targets:"
	@echo ""
	@echo "  make             Same as 'make regen'."
	@echo "  make regen       Regenerate StylusApp.xcodeproj from project.yml."
	@echo "  make build       Regenerate, then verify-build for iOS device (unsigned)."
	@echo "  make build-sim   Regenerate, then verify-build for iOS Simulator."
	@echo "  make test        Regenerate, then run StylusAppTests on a connected iPhone (or simulator)."
	@echo "  make clean       Wipe build/ and build-ios-* CMake build trees."
