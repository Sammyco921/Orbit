APP_BUNDLE = Orbit.app
APP_BINARY = $(APP_BUNDLE)/Contents/MacOS/Orbit
ENTITLEMENTS = Orbit.entitlements
CODESIGN_IDENTITY ?= -

.PHONY: all lint lint-fix build build-release test run install clean

all: lint build test

lint:
	swiftlint lint --strict Sources/ Tests/

lint-fix:
	swiftlint lint --fix Sources/ Tests/

build:
	swift build
	cp .build/debug/Orbit "$(APP_BINARY)"
	codesign --force --sign "$(CODESIGN_IDENTITY)" --entitlements "$(ENTITLEMENTS)" "$(APP_BUNDLE)" 2>/dev/null || true

build-release:
	swift build -c release
	cp .build/release/Orbit "$(APP_BINARY)"
	codesign --force --sign "$(CODESIGN_IDENTITY)" --entitlements "$(ENTITLEMENTS)" "$(APP_BUNDLE)" 2>/dev/null || true

test:
	swift test

run: build
	open "$(APP_BUNDLE)"

install: build-release
	rm -rf /Applications/Orbit.app
	cp -R "$(APP_BUNDLE)" /Applications/
	open /Applications/Orbit.app

clean:
	swift package clean
	rm -rf .build
