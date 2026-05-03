SWIFT_CACHE := $(CURDIR)/.build/swiftpm-cache
CLANG_CACHE := $(CURDIR)/.build/clang-module-cache
SWIFT := env CLANG_MODULE_CACHE_PATH=$(CLANG_CACHE) swift
SWIFT_FLAGS := --disable-sandbox --cache-path $(SWIFT_CACHE)
PREFIX ?= $(HOME)/.local
INSTALL_BIN := $(PREFIX)/bin
XCODE_DERIVED_DATA := $(CURDIR)/.build/XcodeDerivedData
XCODE_APP := $(XCODE_DERIVED_DATA)/Build/Products/Debug/Composer.app
RUNTIME_HELPER := composer-runtime-helper
LAUNCH_AGENT_LABEL := dev.janneh.composer.runtime-helper
LAUNCH_AGENT_TEMPLATE := Resources/LaunchAgents/$(LAUNCH_AGENT_LABEL).plist
LAUNCH_AGENT_PLIST := $(HOME)/Library/LaunchAgents/$(LAUNCH_AGENT_LABEL).plist
LAUNCH_AGENT_LOG_DIR := $(HOME)/Library/Logs/Composer

.PHONY: help build build-cli helper install-helper unload-helper xcode-build test app cli smoke-cli smoke-cli-sqlite ui-screenshots ui-check open-project clean

help:
	@echo "Targets:"
	@echo "  make test             Build and run tests"
	@echo "  make build            Build CLI and macOS app"
	@echo "  make helper           Build composer-runtime-helper"
	@echo "  make install-helper   Install and bootstrap the runtime LaunchAgent"
	@echo "  make unload-helper    Boot out the runtime LaunchAgent"
	@echo "  make xcode-build      Build Composer.app"
	@echo "  make app              Build and open Composer.app"
	@echo "  make open-project     Open Composer.xcodeproj"
	@echo "  make cli              Install composerctl to $(INSTALL_BIN)"
	@echo "  make smoke-cli        Run CLI smoke test against /tmp"
	@echo "  make smoke-cli-sqlite Run CLI smoke test against SQLite in /tmp"
	@echo "  make ui-screenshots   Capture deterministic Composer UI screenshots"
	@echo "  make ui-check         Compare UI screenshots against references"
	@echo "  make clean            Remove .build"

build: xcode-build build-cli helper

build-cli:
	$(SWIFT) build $(SWIFT_FLAGS) --product composerctl

helper:
	$(SWIFT) build $(SWIFT_FLAGS) --product $(RUNTIME_HELPER)

xcode-build:
	xcodebuild -project Composer.xcodeproj -scheme Composer -configuration Debug -derivedDataPath "$(XCODE_DERIVED_DATA)" build

test:
	$(SWIFT) test $(SWIFT_FLAGS)

app: xcode-build
	open "$(XCODE_APP)"

open-project:
	open Composer.xcodeproj

cli: build-cli
	@mkdir -p "$(INSTALL_BIN)"
	@BIN_PATH="$$($(SWIFT) build $(SWIFT_FLAGS) --show-bin-path)"; \
	cp "$$BIN_PATH/composerctl" "$(INSTALL_BIN)/composerctl"; \
	chmod +x "$(INSTALL_BIN)/composerctl"
	@echo "Installed $(INSTALL_BIN)/composerctl"
	@case ":$$PATH:" in *":$(INSTALL_BIN):"*) ;; *) echo "Add $(INSTALL_BIN) to PATH to run composerctl directly.";; esac

install-helper: helper
	@mkdir -p "$(INSTALL_BIN)" "$(HOME)/Library/LaunchAgents" "$(LAUNCH_AGENT_LOG_DIR)"
	@BIN_PATH="$$($(SWIFT) build $(SWIFT_FLAGS) --show-bin-path)"; \
	cp "$$BIN_PATH/$(RUNTIME_HELPER)" "$(INSTALL_BIN)/$(RUNTIME_HELPER)"; \
	chmod +x "$(INSTALL_BIN)/$(RUNTIME_HELPER)"; \
	sed \
		-e "s#__COMPOSER_RUNTIME_HELPER__#$(INSTALL_BIN)/$(RUNTIME_HELPER)#g" \
		-e "s#__COMPOSER_RUNTIME_LOG__#$(LAUNCH_AGENT_LOG_DIR)/runtime-helper.log#g" \
		-e "s#__COMPOSER_RUNTIME_ERROR_LOG__#$(LAUNCH_AGENT_LOG_DIR)/runtime-helper.err.log#g" \
		"$(LAUNCH_AGENT_TEMPLATE)" > "$(LAUNCH_AGENT_PLIST)"
	@launchctl bootout "gui/$$(id -u)" "$(LAUNCH_AGENT_PLIST)" >/dev/null 2>&1 || true
	@launchctl bootstrap "gui/$$(id -u)" "$(LAUNCH_AGENT_PLIST)"
	@launchctl enable "gui/$$(id -u)/$(LAUNCH_AGENT_LABEL)"
	@echo "Installed $(INSTALL_BIN)/$(RUNTIME_HELPER)"
	@echo "Loaded $(LAUNCH_AGENT_PLIST)"

unload-helper:
	@launchctl bootout "gui/$$(id -u)" "$(LAUNCH_AGENT_PLIST)" >/dev/null 2>&1 || true
	@echo "Unloaded $(LAUNCH_AGENT_PLIST)"

smoke-cli: build-cli
	@STORE_PATH=/tmp/composer-cli-smoke.json; \
	BIN_PATH="$$($(SWIFT) build $(SWIFT_FLAGS) --show-bin-path)"; \
	COMPOSERCTL="$$BIN_PATH/composerctl"; \
	rm -f $$STORE_PATH; \
	$$COMPOSERCTL --store $$STORE_PATH project add --name Smoke --agent codex; \
	$$COMPOSERCTL --store $$STORE_PATH task add --project Smoke --title "Smoke task" --state ready --priority high --label cli --agent claude; \
	$$COMPOSERCTL --store $$STORE_PATH task move --project Smoke --task LOCAL-1 --state human-review; \
	$$COMPOSERCTL --store $$STORE_PATH task list --project Smoke --state human-review

smoke-cli-sqlite: build-cli
	@STORE_PATH=/tmp/composer-cli-smoke.sqlite3; \
	BIN_PATH="$$($(SWIFT) build $(SWIFT_FLAGS) --show-bin-path)"; \
	COMPOSERCTL="$$BIN_PATH/composerctl"; \
	rm -f $$STORE_PATH; \
	$$COMPOSERCTL --store-backend sqlite --store $$STORE_PATH project add --name Smoke --agent codex; \
	$$COMPOSERCTL --store-backend sqlite --store $$STORE_PATH task add --project Smoke --title "Smoke task" --state ready --priority high --label cli --agent claude; \
	$$COMPOSERCTL --store-backend sqlite --store $$STORE_PATH task move --project Smoke --task LOCAL-1 --state human-review; \
	$$COMPOSERCTL --store-backend sqlite --store $$STORE_PATH task list --project Smoke --state human-review

ui-screenshots:
	Scripts/capture-ui-screenshots.sh capture

ui-check:
	Scripts/capture-ui-screenshots.sh check

clean:
	rm -rf .build
