# Makefile for Go multi-module workspace

SHELL := /usr/bin/env bash

# Go parameters
GOCMD=go
GOBUILD=$(GOCMD) build
GOCLEAN=$(GOCMD) clean
GOTEST=$(GOCMD) test
GOMOD=$(GOCMD) mod
GOLINT=golangci-lint
GOIMPORTS=goimports

# Build and artifacts
BUILD_DIR=build
COVER_DIR=coverage

# Auto-discover submodules (directories that contain go.mod, excluding repository root)
# Use portable find-based discovery to avoid requiring git during local runs.
MODULES := $(shell find . -type f -name go.mod -not -path './go.mod' -exec dirname {} \; | sed 's|^./||' | sort -u)

.PHONY: all modules build run test test-coverage clean lint deps fmt goimports verify install-tools changelog-create module-create help

# Default entrypoint runs common tasks across all modules
all: deps verify fmt goimports lint build test

# Show discovered modules
modules:
	@echo "Discovered modules:" && \
	printf '  - %s\n' $(MODULES)

# Install and tidy dependencies for all modules
deps:
	@set -e; \
	for m in $(MODULES); do \
		echo "==> deps in $$m"; \
		( cd "$$m" && $(GOMOD) download && $(GOMOD) tidy ); \
	done

# Verify dependencies for all modules
verify:
	@set -e; \
	for m in $(MODULES); do \
		echo "==> verify in $$m"; \
		( cd "$$m" && $(GOMOD) verify ); \
	done

# Build packages
# Usage:
#   make build                -> go build ./... in each module
#   make build MODULE=path    -> build specific module packages
build:
	@mkdir -p $(BUILD_DIR); \
	set -e; \
	if [ -n "$(MODULE)" ]; then \
		echo "==> build in $(MODULE)"; \
		( cd "$(MODULE)" && $(GOBUILD) ./... ); \
	else \
		for m in $(MODULES); do \
			echo "==> build in $$m"; \
			( cd "$$m" && $(GOBUILD) ./... ); \
		done; \
	fi

# Run tests across modules
# Usage:
#   make test                 -> go test ./... in each module
#   make test MODULE=path     -> test specific module
test:
	@set -e; \
	if [ -n "$(MODULE)" ]; then \
		echo "==> test in $(MODULE)"; \
		( cd "$(MODULE)" && $(GOTEST) -v ./... ); \
	else \
		for m in $(MODULES); do \
			echo "==> test in $$m"; \
			( cd "$$m" && $(GOTEST) -v ./... ); \
		done; \
	fi

# Run tests with coverage per module (writes separate coverage files)
# Combined report merging is intentionally omitted to keep this simple.
# Usage: make test-coverage [MODULE=path]
test-coverage:
	@COVER_ABS="$(CURDIR)/$(COVER_DIR)"; \
	mkdir -p "$$COVER_ABS"; \
	set -e; \
	if [ -n "$(MODULE)" ]; then \
		m=$(MODULE); \
		echo "==> coverage in $$m"; \
		( cd "$$m" && $(GOTEST) -v -coverprofile="$$COVER_ABS/$$(echo $$m | tr '/' '_').out" ./... ); \
	else \
		for m in $(MODULES); do \
			echo "==> coverage in $$m"; \
			( cd "$$m" && $(GOTEST) -v -coverprofile="$$COVER_ABS/$$(echo $$m | tr '/' '_').out" ./... ); \
		done; \
	fi

# Clean build artifacts
clean:
	$(GOCLEAN)
	rm -rf $(BUILD_DIR) $(COVER_DIR) coverage.out coverage.html || true

# Lint each module using golangci-lint
lint:
	@which $(GOLINT) >/dev/null 2>&1 || (echo "Installing golangci-lint..." && \
		GOBIN=$$(go env GOPATH)/bin GOFLAGS= go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest); \
	set -e; \
	if [ -n "$(MODULE)" ]; then \
		echo "==> lint in $(MODULE)"; \
		$(GOLINT) run --timeout=5m --path-prefix "$(MODULE)" -c .golangci.yml --out-format=tab ./$(MODULE)/...; \
	else \
		for m in $(MODULES); do \
			echo "==> lint in $$m"; \
			$(GOLINT) run --timeout=5m --path-prefix "$$m" -c .golangci.yml --out-format=tab ./$$m/...; \
		done; \
	fi

# Format code
fmt:
	$(GOCMD) fmt ./...

# Run goimports
goimports:
	@which $(GOIMPORTS) >/dev/null 2>&1 || go install golang.org/x/tools/cmd/goimports@latest
	$(GOIMPORTS) -w ./

# Run a module (requires MODULE=path)
run:
	@if [ -z "$(MODULE)" ]; then \
		echo "Please specify MODULE=<path/to/module> (e.g., http/gin)"; \
		exit 1; \
	fi; \
	echo "==> run in $(MODULE)"; \
	cd "$(MODULE)" && $(GOCMD) run ./...

install-tools:
	@set -e; \
	echo "Installing AWS multi-module tools..."; \
	$(GOCMD) install github.com/awslabs/aws-go-multi-module-repository-tools/cmd/makerelative@latest; \
	$(GOCMD) install github.com/awslabs/aws-go-multi-module-repository-tools/cmd/updaterequires@latest; \
	$(GOCMD) install github.com/awslabs/aws-go-multi-module-repository-tools/cmd/calculaterelease@latest; \
	$(GOCMD) install github.com/awslabs/aws-go-multi-module-repository-tools/cmd/tagrelease@latest; \
	$(GOCMD) install github.com/awslabs/aws-go-multi-module-repository-tools/cmd/generatechangelog@latest; \
	$(GOCMD) install github.com/awslabs/aws-go-multi-module-repository-tools/cmd/changelog@latest

# Generate a changelog entry (Non-Interactive)
# Usage:
#   make changelog-create RELEASE="v1.2.3" PACKAGE="http/gin"
# This will create a rolled-up `release` type changelog entry with the given release description for the specified module.
changelog-create:
	@if ! command -v changelog >/dev/null 2>&1; then \
		echo "changelog CLI not found. Run 'make install-tools' to install it."; \
		exit 1; \
	fi; \
	if [ -z "$(RELEASE)" ] || [ -z "$(PACKAGE)" ]; then \
		echo "Usage: make changelog-create RELEASE=\"<release-id-or-desc>\" PACKAGE=\"<module-path>\""; \
		echo "Example: make changelog-create RELEASE=\"v1.2.3\" PACKAGE=\"http/gin\""; \
		exit 2; \
	fi; \
	echo "==> creating changelog entry: type=release, package=$(PACKAGE), description=$(RELEASE)"; \
	changelog create -ni -r -t release -d "$(RELEASE)" "$(PACKAGE)"

# Create a new module
# Usage:
#   make module-create MODULE="path/to/module"
# This will:
#  - create the module directory with a minimal go.mod and placeholder .go
#  - update modman.toml with a new [modules."<MODULE>"] block
#  - create a default changelog entry with description v1.0.0 for the module
module-create:
	@if [ -z "$(MODULE)" ]; then \
		echo "Usage: make module-create MODULE=\"<path/to/module>\""; \
		echo "Example: make module-create MODULE=\"cache/mem\""; \
		exit 2; \
	fi; \
	set -e; \
	BASE_MOD=$$(awk '/^module /{print $$2}' go.mod); \
	MOD_DIR="$(MODULE)"; \
	if [ -z "$$MOD_DIR" ] || [ "$$MOD_DIR" = "/" ]; then \
		echo "Error: MODULE is empty or invalid (\"$$MOD_DIR\"). Aborting."; \
		exit 4; \
	fi; \
	if [ -e "$$MOD_DIR" ] && [ ! -d "$$MOD_DIR" ]; then \
		echo "Error: $$MOD_DIR exists and is not a directory"; \
		exit 3; \
	fi; \
	mkdir -p "$$MOD_DIR"; \
	# Create go.mod if not exists
	if [ ! -f "$$MOD_DIR/go.mod" ]; then \
		echo "Creating $$MOD_DIR/go.mod"; \
		( cd "$$MOD_DIR" && $(GOCMD) mod init "$$BASE_MOD/$(MODULE)" && $(GOCMD) mod edit -go=1.25 ); \
	fi; \
	# Create a placeholder .go file if none present
	if ! find "$$MOD_DIR" -maxdepth 1 -type f -name '*.go' | grep -q .; then \
		PKG_NAME=$$(basename "$$MOD_DIR" | tr '-' '_' ); \
		FNAME="$$MOD_DIR/$$PKG_NAME.go"; \
		echo "Creating $$FNAME"; \
		printf "package %s\n\n// Package %s is a placeholder for the new module.\n" "$$PKG_NAME" "$$PKG_NAME" > "$$FNAME"; \
	fi; \
	# Update modman.toml if the module entry does not exist
	if ! grep -E "^[[:space:]]*\[modules\.\"$(MODULE)\"\]" modman.toml >/dev/null 2>&1; then \
		echo "Updating modman.toml with module $(MODULE)"; \
		{ \
			echo "    [modules.\"$(MODULE)\"]"; \
			echo "        no_tag = false"; \
			echo "        pre_release=\"\""; \
		} >> modman.toml; \
	else \
		echo "modman.toml already contains module $(MODULE); skipping update"; \
	fi; \
	# Ensure changelog tool and create default entry v1.0.0
	if ! command -v changelog >/dev/null 2>&1; then \
		echo "changelog CLI not found. Run 'make install-tools' to install it."; \
		exit 1; \
	fi; \
	echo "==> creating default changelog entry for $(MODULE): v1.0.0"; \
	changelog create -ni -r -t release -d "v1.0.0" "$(MODULE)"

# Help
help:
	@echo "Make targets:"
	@echo "  modules        - Show discovered Go modules"
	@echo "  all            - deps, verify, fmt, goimports, lint, build, test across modules"
	@echo "  deps           - Download and tidy dependencies per module"
	@echo "  verify         - Verify dependencies per module"
	@echo "  build          - Build packages; use MODULE=path to target a single module"
	@echo "  run            - Run a module; requires MODULE=path (e.g., http/gin)"
	@echo "  test           - Run tests; use MODULE=path to target a single module"
	@echo "  test-coverage  - Run tests with coverage per module (outputs in $(COVER_DIR)/)"
	@echo "  lint           - Run golangci-lint per module"
	@echo "  fmt            - go fmt across the workspace"
	@echo "  goimports      - goimports across the workspace"
	@echo "  install-tools  - Install AWS multi-module tools (makerelative, updaterequires, calculaterelease, tagrelease, generatechangelog, changelog)"
	@echo "  changelog-create - Create a non-interactive changelog entry; requires RELEASE and PACKAGE"
	@echo "  module-create  - Create a new module with go.mod, placeholder file, modman.toml update, and changelog entry"
	@echo "  help           - Show this help"
