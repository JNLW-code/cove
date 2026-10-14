# Cove — build, run, install, remove. Every target is a plain command you can read.
APP        := Cove
BUNDLE     := com.jameswebster.cove
IDENTITY   := Cove Dev
BUILD      := .build/release
OUT        := build/$(APP).app
HOOKS      := $(HOME)/.claude/island
SWIFTFLAGS := -c release -Xswiftc -warnings-as-errors
VERSION    := $(shell /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Support/Info.plist)
DMG        := build/Cove.dmg
STAGE      := build/dmg

.PHONY: check build run install install-hooks uninstall cert quit clean fake dmg test-dmg release

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
	codesign --force --sign "$(IDENTITY)" --identifier $(BUNDLE).hook $(BUILD)/cove-hook

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

## install-hooks: put the hook script and helper in ~/.claude/island (then paste hooks/settings-snippet.json into ~/.claude/settings.json)
install-hooks: check
	mkdir -p $(HOOKS)
	cp hooks/hook.sh $(HOOKS)/hook.sh
	cp $(BUILD)/cove-hook $(HOOKS)/cove-hook
	chmod 755 $(HOOKS)/hook.sh $(HOOKS)/cove-hook
	@echo "Installed $(HOOKS)/hook.sh and cove-hook. Add the entries from hooks/settings-snippet.json to ~/.claude/settings.json."

## fake: drive every Claude state through the socket (app must be running)
fake:
	scripts/fake-events.sh

## dmg: build/Cove.dmg with the app, an Applications shortcut, the hook files, the install script and the Read Me
dmg: build
	rm -rf $(STAGE) $(DMG)
	mkdir -p $(STAGE)/Hooks
	cp -R $(OUT) $(STAGE)/Cove.app
	ln -s /Applications $(STAGE)/Applications
	cp hooks/hook.sh $(BUILD)/cove-hook hooks/settings-snippet.json $(STAGE)/Hooks/
	cp "release/Install Hooks.command" "release/Read Me.txt" $(STAGE)/
	hdiutil create -volname "Cove $(VERSION)" -srcfolder $(STAGE) -ov -format UDZO -quiet $(DMG)
	@echo "Built $(DMG) ($$(du -h $(DMG) | cut -f1))"

## test-dmg: mount the dmg, run its install script against a scratch HOME, check the result
test-dmg: dmg
	scripts/test-dmg.sh $(DMG)

## release: tag v$(VERSION), push main and the tag, publish a GitHub release with the dmg attached
release: test-dmg
	@git diff --quiet && git diff --cached --quiet || (echo "Commit your changes first"; exit 1)
	git tag -a v$(VERSION) -m "Cove $(VERSION)"
	git push origin main v$(VERSION)
	gh release create v$(VERSION) $(DMG) --title "Cove $(VERSION)" --notes-file release/notes.md
	@echo "Released Cove $(VERSION)"

## uninstall: quit, remove the app, its data and the hook files (then take the island lines out of ~/.claude/settings.json)
uninstall: quit
	rm -rf ~/Applications/$(APP).app build
	rm -rf "$(HOME)/Library/Application Support/$(APP)"
	rm -rf $(HOOKS)
	@echo "Removed ~/Applications/$(APP).app, its Application Support folder and $(HOOKS)."
	@echo "Now delete every hook entry whose command contains .claude/island/hook.sh from ~/.claude/settings.json."

## cert: make the stable self-signed signing certificate once
cert:
	@scripts/make-cert.sh "$(IDENTITY)"

clean:
	rm -rf .build build
