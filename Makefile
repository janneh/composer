SWIFT_CACHE := $(CURDIR)/.build/swiftpm-cache
CLANG_CACHE := $(CURDIR)/.build/clang-module-cache
SWIFT := env CLANG_MODULE_CACHE_PATH=$(CLANG_CACHE) swift
SWIFT_FLAGS := --disable-sandbox --cache-path $(SWIFT_CACHE)
PREFIX ?= $(HOME)/.local
INSTALL_BIN := $(PREFIX)/bin
XCODE_DERIVED_DATA := $(CURDIR)/.build/XcodeDerivedData
XCODE_APP := $(XCODE_DERIVED_DATA)/Build/Products/Debug/Composer.app

.PHONY: help build build-cli xcode-build test app cli smoke-cli smoke-cli-sqlite open-project clean

help:
	@echo "Targets:"
	@echo "  make test             Build and run tests"
	@echo "  make build            Build CLI and macOS app"
	@echo "  make xcode-build      Build Composer.app"
	@echo "  make app              Build and open Composer.app"
	@echo "  make open-project     Open Composer.xcodeproj"
	@echo "  make cli              Install composerctl to $(INSTALL_BIN)"
	@echo "  make smoke-cli        Run CLI smoke test against /tmp"
	@echo "  make smoke-cli-sqlite Run CLI smoke test against SQLite in /tmp"
	@echo "  make clean            Remove .build"

build: xcode-build build-cli

build-cli:
	$(SWIFT) build $(SWIFT_FLAGS) --product composerctl

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

clean:
	rm -rf .build
