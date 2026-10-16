# Cove — build, run, install, remove. Every target is a plain command you can read.
APP        := Cove
BUNDLE     := com.jameswebster.cove
IDENTITY   := Cove Dev
BUILD      := .build/release
OUT        := build/$(APP).app
HOOKS      := $(HOME)/.claude/island
SWIFTFLAGS := -c release -Xswiftc -warnings-as-errors -Xlinker -rpath -Xlinker @executable_path/../Frameworks
SPARKLE    := .build/artifacts/sparkle/Sparkle
FEED_URL   := https://github.com/JNLW-code/cove/releases/download
VERSION    := $(shell /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Support/Info.plist)
DMG        := build/Cove.dmg
STAGE      := build/dmg

.PHONY: check build run install install-hooks uninstall cert quit clean fake dmg test-dmg appcast release test-update remote test-remote

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
	mkdir -p $(OUT)/Contents/Resources/island
	cp hooks/hook.sh $(BUILD)/cove-hook hooks/settings-snippet.json $(OUT)/Contents/Resources/island/
	mkdir -p $(OUT)/Contents/Frameworks
	cp -R $(SPARKLE)/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework $(OUT)/Contents/Frameworks/
	codesign --force --deep --sign "$(IDENTITY)" $(OUT)/Contents/Frameworks/Sparkle.framework
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
	mkdir -p "$(STAGE)/Claude Code over SSH"
	cp remote/cove-hook.py remote/hook.sh remote/merge-settings.py hooks/settings-snippet.json scripts/install-remote.sh "$(STAGE)/Claude Code over SSH/"
	hdiutil create -volname "Cove $(VERSION)" -srcfolder $(STAGE) -ov -format UDZO -quiet $(DMG)
	@echo "Built $(DMG) ($$(du -h $(DMG) | cut -f1))"

## test-dmg: mount the dmg, run its install script against a scratch HOME, check the result
test-dmg: dmg
	scripts/test-dmg.sh $(DMG)

## appcast: appcast.xml for Sparkle, signed with the EdDSA key in the login keychain, pointing at the GitHub release asset
appcast: dmg
	rm -rf build/updates && mkdir -p build/updates && cp $(DMG) build/updates/Cove.dmg
	$(SPARKLE)/bin/generate_appcast --download-url-prefix "$(FEED_URL)/v$(VERSION)/" \
	    --link "https://github.com/JNLW-code/cove/releases" -o appcast.xml build/updates
	@echo "Wrote appcast.xml for $(VERSION)"

## release: tag v$(VERSION), push main and the tag, publish a GitHub release with the dmg attached, then publish the appcast
release: test-dmg appcast
	@git diff --quiet -- . ':!appcast.xml' && git diff --cached --quiet || (echo "Commit your changes first"; exit 1)
	git tag -a v$(VERSION) -m "Cove $(VERSION)"
	git push origin main v$(VERSION)
	gh release create v$(VERSION) $(DMG) --title "Cove $(VERSION)" --notes-file release/notes.md
	git add appcast.xml && git commit -q -m "appcast: Cove $(VERSION)" && git push origin main
	@echo "Released Cove $(VERSION); installed copies see it on their next check"

## test-update: the current build updates itself from a local feed to a "-test" build (no GitHub involved)
test-update:
	scripts/test-update.sh
	$(MAKE) build

## remote: set up a machine you reach over SSH (make remote HOST=vps): hook files + settings there, RemoteForward here
remote:
	scripts/install-remote.sh $(HOST) $(or $(PORT),47925)

## test-remote: drive the Python helper through a local TCP relay standing in for the SSH tunnel (Cove must be running in test mode)
test-remote:
	scripts/test-remote.sh

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
