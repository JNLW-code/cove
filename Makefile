# Cove — build, run, install, remove. Every target is a plain command you can read.
APP        := Cove
BUNDLE     := com.jameswebster.cove
IDENTITY   := Cove Dev
BUILD      := .build/release
OUT        := build/$(APP).app
SWIFTFLAGS := -c release -Xswiftc -warnings-as-errors

.PHONY: check build run install uninstall cert quit clean

## check: build with warnings as errors (the only build the project does)
check:
	swift build $(SWIFTFLAGS)

## build: check, then assemble and sign build/Cove.app
build: check cert
	rm -rf $(OUT)
	mkdir -p $(OUT)/Contents/MacOS $(OUT)/Contents/Resources
	cp $(BUILD)/$(APP) $(OUT)/Contents/MacOS/$(APP)
	cp Support/Info.plist $(OUT)/Contents/Info.plist
	/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $$(git rev-list --count HEAD 2>/dev/null || echo 1)" $(OUT)/Contents/Info.plist
	printf 'APPL????' > $(OUT)/Contents/PkgInfo
	codesign --force --sign "$(IDENTITY)" --identifier $(BUNDLE) $(OUT)
	codesign --verify --verbose=1 $(OUT)

## quit: stop any running copy
quit:
	@pkill -x $(APP) 2>/dev/null && sleep 0.5 || true

## run: quit the old copy, build, launch from build/
run: quit build
	open $(OUT)
	@sleep 1; pgrep -x $(APP) >/dev/null && echo "$(APP) running, pid $$(pgrep -x $(APP))" || (echo "$(APP) did not start"; exit 1)

## install: put a fresh copy in ~/Applications and launch it (launch at login only works from there)
install: quit build
	mkdir -p ~/Applications
	rm -rf ~/Applications/$(APP).app
	cp -R $(OUT) ~/Applications/$(APP).app
	open ~/Applications/$(APP).app

## uninstall: quit, remove the app and its data (see README for the settings.json lines)
uninstall: quit
	rm -rf ~/Applications/$(APP).app build
	rm -rf "$(HOME)/Library/Application Support/$(APP)"
	@echo "Removed ~/Applications/$(APP).app and its Application Support folder."

## cert: make the stable self-signed signing certificate once
cert:
	@scripts/make-cert.sh "$(IDENTITY)"

clean:
	rm -rf .build build
