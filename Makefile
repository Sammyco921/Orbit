APP_BUNDLE = Orbit.app
APP_BINARY = $(APP_BUNDLE)/Contents/MacOS/Orbit

.PHONY: all lint lint-fix build test run clean install

all: lint build test

lint:
	swiftlint lint --strict Sources/ Tests/

lint-fix:
	swiftlint lint --fix Sources/ Tests/

build:
	swift build
	cp .build/debug/Orbit "$(APP_BINARY)"

test:
	swift test

run: build
	open "$(APP_BUNDLE)"

install: build
	rm -rf /Applications/Orbit.app
	cp -R "$(APP_BUNDLE)" /Applications/
	open /Applications/Orbit.app

clean:
	swift package clean
	rm -rf .build
