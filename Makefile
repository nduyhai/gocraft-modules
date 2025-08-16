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

.PHONY: all modules build run test test-coverage clean lint deps fmt goimports verify help

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
	@echo "  help           - Show this help"
