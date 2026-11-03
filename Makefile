# Keepwell — development tasks. Run `make help` for the list.
SHELL := /bin/bash
.DEFAULT_GOAL := help

PROJECT      := Keepwell.xcodeproj
SCHEME       := Keepwell
CONFIG       ?= Debug
DERIVED_DATA := build/DerivedData
RESULTS      := build/Results
MISE         := mise exec --
DESTINATION   = $(shell scripts/simulator-destination.sh)
# Package.resolved is committed at the root because the .xcodeproj is not.
RESOLVED      := Package.resolved
PROJECT_RESOLVED := $(PROJECT)/project.xcworkspace/xcshareddata/swiftpm/Package.resolved

# -skipMacroValidation: the Point-Free packages depend on swift-syntax (macros) and CI has no trust prompt.
XCODEBUILD = set -o pipefail && xcodebuild \
	-project $(PROJECT) \
	-scheme "$(SCHEME)" \
	-configuration $(CONFIG) \
	-destination "$(DESTINATION)" \
	-derivedDataPath $(DERIVED_DATA) \
	-skipMacroValidation \
	-skipPackagePluginValidation \
	-quiet \
	$(XCODEBUILD_FLAGS)

APP_PATH      := $(DERIVED_DATA)/Build/Products/$(CONFIG)-iphonesimulator/Keepwell.app
DEVICE_HUB    := $(shell xcode-select -p)/../Applications/DeviceHub.app

.PHONY: help bootstrap tools generate resolve hooks open run lint format build test test-unit test-ui test-record-snapshots clean

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-22s\033[0m %s\n", $$1, $$2}'

bootstrap: tools generate hooks ## Install tools, generate the project and install hooks
	@echo "✔ Done. Open the project with 'make open' or launch it with 'make run'."

tools: ## Install the versions pinned in .mise.toml
	@command -v mise >/dev/null || { echo "✖ mise is missing: brew install mise (https://mise.jdx.dev)"; exit 1; }
	mise trust --quiet .
	mise install

generate: ## Generate Keepwell.xcodeproj with XcodeGen (uses the committed Package.resolved)
	$(MISE) xcodegen generate --quiet
	@if [ -f $(RESOLVED) ]; then mkdir -p $(dir $(PROJECT_RESOLVED)) && cp $(RESOLVED) $(PROJECT_RESOLVED); fi

resolve: generate ## Resolve SPM packages and update the committed Package.resolved
	xcodebuild -project $(PROJECT) -scheme "$(SCHEME)" -resolvePackageDependencies -skipMacroValidation -skipPackagePluginValidation -quiet
	cp $(PROJECT_RESOLVED) $(RESOLVED)
	@echo "✔ $(RESOLVED) updated."

hooks: ## Install the lefthook git hooks
	$(MISE) lefthook install

open: generate ## Generate and open the project in Xcode
	open $(PROJECT)

run: build ## Build, install and launch the app on the simulator (shown in DeviceHub)
	@udid="$$(scripts/simulator-destination.sh | sed 's/.*id=//')"; \
	xcrun simctl boot "$$udid" 2>/dev/null || true; \
	xcrun simctl bootstatus "$$udid" -b >/dev/null; \
	if [ -d "$(DEVICE_HUB)" ]; then open "$(DEVICE_HUB)"; else open -a Simulator; fi; \
	bundle_id="$$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$(APP_PATH)/Info.plist")"; \
	xcrun simctl install "$$udid" "$(APP_PATH)" && \
	xcrun simctl launch --terminate-running-process "$$udid" "$$bundle_id"

lint: ## SwiftFormat (lint mode) + strict SwiftLint
	$(MISE) swiftformat --lint .
	$(MISE) swiftlint lint --strict --quiet

format: ## Format code and apply SwiftLint autocorrections
	$(MISE) swiftformat .
	$(MISE) swiftlint lint --fix --quiet

build: generate ## Build the app for the simulator
	$(XCODEBUILD) build

test: generate ## Package unit tests + UI tests, with coverage
	rm -rf $(RESULTS)/All.xcresult
	$(XCODEBUILD) -resultBundlePath $(RESULTS)/All.xcresult test

test-unit: generate ## Package unit tests only (used by pre-push)
	rm -rf $(RESULTS)/Unit.xcresult
	$(XCODEBUILD) -resultBundlePath $(RESULTS)/Unit.xcresult -skip-testing:KeepwellUITests test

test-ui: generate ## UI tests only
	rm -rf $(RESULTS)/UI.xcresult
	$(XCODEBUILD) -resultBundlePath $(RESULTS)/UI.xcresult -only-testing:KeepwellUITests test

test-record-snapshots: generate ## Re-record snapshot test reference images
	SNAPSHOT_TESTING_RECORD=all TEST_RUNNER_SNAPSHOT_TESTING_RECORD=all \
		$(XCODEBUILD) -only-testing:DesignSystemTests test || true
	@echo "Review and commit the changes under Packages/*/Tests/**/__Snapshots__."

clean: ## Delete build artifacts and the generated project
	rm -rf build $(PROJECT)
