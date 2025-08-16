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

.PHONY: all modules build run test test-coverage clean lint deps fmt goimports verify docker-build docker-buildx docker-run docker-clean help makerelative unmakerelative updaterequires calculaterelease tagrelease generatechangelog changelog install-tools

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
		cd "$$m" && $(GOMOD) download && $(GOMOD) tidy; \
	done

# Verify dependencies for all modules
verify:
	@set -e; \
	for m in $(MODULES); do \
		echo "==> verify in $$m"; \
		cd "$$m" && $(GOMOD) verify; \
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
		cd "$(MODULE)" && $(GOBUILD) ./...; \
	else \
		for m in $(MODULES); do \
			echo "==> build in $$m"; \
			cd "$$m" && $(GOBUILD) ./...; \
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
		cd "$(MODULE)" && $(GOTEST) -v ./...; \
	else \
		for m in $(MODULES); do \
			echo "==> test in $$m"; \
			cd "$$m" && $(GOTEST) -v ./...; \
		done; \
	fi

# Run tests with coverage per module (writes separate coverage files)
# Combined report merging is intentionally omitted to keep this simple.
# Usage: make test-coverage [MODULE=path]
test-coverage:
	@mkdir -p $(COVER_DIR); \
	set -e; \
	if [ -n "$(MODULE)" ]; then \
		m=$(MODULE); \
		echo "==> coverage in $$m"; \
		cd "$$m" && $(GOTEST) -v -coverprofile="../$(COVER_DIR)/$$(echo $$m | tr '/' '_').out" ./...; \
	else \
		for m in $(MODULES); do \
			echo "==> coverage in $$m"; \
			cd "$$m" && $(GOTEST) -v -coverprofile="../$(COVER_DIR)/$$(echo $$m | tr '/' '_').out" ./...; \
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

# Docker targets are kept as-is; they assume a Dockerfile at repo root
# and may not directly build a specific module binary.
DOCKER_IMAGE_NAME=gocraft-modules-app
DOCKER_IMAGE_TAG=latest
DOCKERFILE=Dockerfile

docker-build:
	@echo "Building Docker image $(DOCKER_IMAGE_NAME):$(DOCKER_IMAGE_TAG)..."
	docker build -t $(DOCKER_IMAGE_NAME):$(DOCKER_IMAGE_TAG) -f $(DOCKERFILE) .

docker-buildx:
	@echo "Building multi-arch Docker image $(DOCKER_IMAGE_NAME):$(DOCKER_IMAGE_TAG)..."
	docker buildx build \
		--platform linux/amd64,linux/arm64 \
		-t $(DOCKER_IMAGE_NAME):$(DOCKER_IMAGE_TAG) \
		-f $(DOCKERFILE) \
		--load \
		.

docker-run:
	@echo "Running Docker container..."
	docker run --rm -p 8080:8080 $(DOCKER_IMAGE_NAME):$(DOCKER_IMAGE_TAG)

docker-clean:
	@echo "Removing Docker image..."
	docker rmi $(DOCKER_IMAGE_NAME):$(DOCKER_IMAGE_TAG) || true

# --- AWS tools convenience targets ---
# makerelative: use the standalone AWS tool to add local replace directives so
# inter-module imports resolve to the local checkout during development.
makerelative:
	@set -e; \
	command -v makerelative >/dev/null 2>&1 || { echo "makerelative tool not found. Run: make install-tools"; exit 1; }; \
	makerelative --config modman.toml

unmakerelative:
	@set -e; \
	MARK_BEGIN='# BEGIN makerelative (auto-generated)'; \
	MARK_END='# END makerelative (auto-generated)'; \
	for m in $(MODULES); do \
		gomod="$$m/go.mod"; \
		echo "==> unmakerelative in $$m"; \
		awk -v b="$$MARK_BEGIN" -v e="$$MARK_END" 'BEGIN{skip=0} { if($$0==b){skip=1; next} if($$0==e){skip=0; next} if(!skip) print $$0 }' "$$gomod" > "$$gomod.tmp"; \
		mv "$$gomod.tmp" "$$gomod"; \
	done

# Install standalone AWS multi-module tools locally
install-tools:
	@set -e; \
	echo "Installing AWS multi-module tools..."; \
	$(GOCMD) install github.com/awslabs/aws-go-multi-module-repository-tools/cmd/makerelative@latest; \
	$(GOCMD) install github.com/awslabs/aws-go-multi-module-repository-tools/cmd/updaterequires@latest; \
	$(GOCMD) install github.com/awslabs/aws-go-multi-module-repository-tools/cmd/calculaterelease@latest; \
	$(GOCMD) install github.com/awslabs/aws-go-multi-module-repository-tools/cmd/tagrelease@latest; \
	$(GOCMD) install github.com/awslabs/aws-go-multi-module-repository-tools/cmd/generatechangelog@latest; \
	$(GOCMD) install github.com/awslabs/aws-go-multi-module-repository-tools/cmd/changelog@latest

# The following targets act as thin wrappers preferring standalone tools, with fallback to ModMan CLI if available.
# Install standalone tools via: make install-tools
# Or install ModMan CLI via: go install github.com/awslabs/aws-go-multi-module-repository-tools/cmd/modman@latest
updaterequires:
	@set -e; \
	command -v updaterequires >/dev/null 2>&1 || { echo "updaterequires tool not found. Run: make install-tools"; exit 1; }; \
	updaterequires --config modman.toml

calculaterelease:
	@set -e; \
	command -v calculaterelease >/dev/null 2>&1 || { echo "calculaterelease tool not found. Run: make install-tools"; exit 1; }; \
	if [ -n "$(BUMP)" ]; then calculaterelease --config modman.toml --bump "$(BUMP)"; else calculaterelease --config modman.toml; fi

tagrelease:
	@set -e; \
	command -v tagrelease >/dev/null 2>&1 || { echo "tagrelease tool not found. Run: make install-tools"; exit 1; }; \
	if [ -n "$(DRY_RUN)" ]; then tagrelease --config modman.toml --dry-run; else tagrelease --config modman.toml; fi

generatechangelog:
	@set -e; \
	command -v generatechangelog >/dev/null 2>&1 || { echo "generatechangelog tool not found. Run: make install-tools"; exit 1; }; \
	generatechangelog --config modman.toml --output CHANGELOG.md

changelog:
	@set -e; \
	command -v changelog >/dev/null 2>&1 || { echo "changelog tool not found. Install with: make install-tools"; exit 1; }; \
	changelog --config modman.toml --output CHANGELOG.md

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
	@echo "  makerelative   - Add local replace directives for internal modules (uses AWS tool)"
	@echo "  unmakerelative - Remove local replace directives previously added"
	@echo "  updaterequires - Bulk-update external dependencies as per modman.toml"
	@echo "  calculaterelease - Compute next per-module versions (uses modman.toml)"
	@echo "  tagrelease     - Create per-module tags (uses modman.toml)"
	@echo "  generatechangelog - Generate CHANGELOG.md (uses modman.toml)"
	@echo "  changelog      - Render changelog using modman.toml"
	@echo "  docker-build   - Build Docker image from repo root Dockerfile"
	@echo "  docker-buildx  - Build multi-arch Docker image"
	@echo "  docker-run     - Run the Docker container"
	@echo "  docker-clean   - Remove the Docker image"
	@echo "  help           - Show this help"
