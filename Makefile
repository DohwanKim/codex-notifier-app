APP_NAME := Codex Notifier
BUNDLE_ID := com.dohwankim.codex-notifier
CONFIGURATION ?= release
BUILD_DIR := .build/$(CONFIGURATION)
APP_DIR := build/$(APP_NAME).app
CONTENTS_DIR := $(APP_DIR)/Contents
MACOS_DIR := $(CONTENTS_DIR)/MacOS
RESOURCES_DIR := $(CONTENTS_DIR)/Resources
ICON_FILE := packaging/AppIcon.icns

.PHONY: test build icon app clean install

test:
	swift test

build:
	swift build -c $(CONFIGURATION)

icon:
	swift scripts/generate_app_icon.swift
	iconutil -c icns packaging/AppIcon.iconset -o "$(ICON_FILE)"

app: build icon
	rm -rf "$(APP_DIR)"
	mkdir -p "$(MACOS_DIR)" "$(RESOURCES_DIR)"
	cp packaging/Info.plist "$(CONTENTS_DIR)/Info.plist"
	cp "$(BUILD_DIR)/CodexNotifierApp" "$(MACOS_DIR)/$(APP_NAME)"
	cp "$(BUILD_DIR)/codex-notifier-helper" "$(MACOS_DIR)/codex-notifier-helper"
	cp "$(ICON_FILE)" "$(RESOURCES_DIR)/AppIcon.icns"
	if [ -f "/System/Library/Sounds/Glass.aiff" ]; then cp "/System/Library/Sounds/Glass.aiff" "$(RESOURCES_DIR)/CodexPing.aiff"; fi
	xattr -cr "$(APP_DIR)"
	codesign --force --deep --sign - "$(APP_DIR)"
	xattr -cr "$(APP_DIR)"
	@echo "$(APP_DIR)"

install: app
	rm -rf "/Applications/$(APP_NAME).app"
	cp -R "$(APP_DIR)" /Applications/
	# Cloud-synced workspaces can attach FinderInfo to copied app bundles, and strict codesign rejects those xattrs.
	xattr -cr "/Applications/$(APP_NAME).app"

clean:
	rm -rf .build build
