# gocraft-modules

[![Go](https://img.shields.io/badge/go-1.25+-blue)](https://go.dev/)
[![License](https://img.shields.io/github/license/nduyhai/gocraft-modules)](LICENSE)
[![Multi-Module CI](https://github.com/nduyhai/gocraft-modules/actions/workflows/multi-module-ci.yml/badge.svg)](https://github.com/nduyhai/gocraft-modules/actions/workflows/multi-module-ci.yml)
[![AWS Tools](https://github.com/nduyhai/gocraft-modules/actions/workflows/modman-tools.yml/badge.svg)](https://github.com/nduyhai/gocraft-modules/actions/workflows/modman-tools.yml)

A Go multi-module workspace with examples for HTTP (chi, gin), gRPC (client, server), and DB (gorm). The repo includes a multi-module aware Makefile, CI, and integration with AWS Labs’ multi-module repository tools.

## Modules

- db/gorm
- grpc/client
- grpc/server
- http/chi
- http/gin

See go.work for the complete workspace list.

## Requirements

- Go 1.25+
- Optional: Docker (for docker-build targets)

## Quickstart

```bash
# Clone
git clone https://github.com/nduyhai/gocraft-modules
cd gocraft-modules

# Show discovered modules
make modules

# Install deps, verify, format, lint, build, and test across all modules
make all

# Install AWS multi-module tools locally (used by some Makefile targets)
make install-tools

# For local development, map inter-module imports to your checkout
make makerelative   # adds replace blocks to submodule go.mod files
# ...hack on code...
make unmakerelative # removes those replace blocks

# Run tests (all modules or a single module)
make test
make test MODULE=http/gin

# Lint all modules (or one)
make lint
make lint MODULE=grpc/server
```

## Using AWS Multi-Module Tools

This repo uses the standalone tools from https://github.com/awslabs/aws-go-multi-module-repository-tools, configured by modman.toml at the repo root.

Install tools:

```bash
make install-tools
```

Common commands:

- make updaterequires — bulk-bump external dependencies per modman.toml
- make calculaterelease [BUMP=auto|major|minor|patch] — compute next versions per module
- make tagrelease [DRY_RUN=1] — create tags (use DRY_RUN to preview)
- make generatechangelog — generate CHANGELOG.md
- make changelog — render changelog

## CI

- .github/workflows/multi-module-ci.yml: discovers modules and runs tidy/verify, build, test, lint per module.
- .github/workflows/modman-tools.yml (named "AWS Tools"): installs the standalone tools and allows running makerelative, updaterequires, calculaterelease, tagrelease, and changelog generation via workflow_dispatch.

## Makefile Targets (highlights)

- modules — list discovered modules
- deps, verify — manage dependencies per module
- build, test, test-coverage — with optional MODULE=path selector
- lint, fmt, goimports — code quality
- install-tools — install the AWS multi-module tool binaries
- makerelative / unmakerelative — add/remove local replace blocks for inter-module dev
- updaterequires, calculaterelease, tagrelease, generatechangelog, changelog — tool wrappers using modman.toml
- docker-build, docker-buildx, docker-run, docker-clean — container helpers

Run make help for the full list.

## License

MIT — see LICENSE.

