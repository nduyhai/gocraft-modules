# gocraft-modules

[![Go](https://img.shields.io/badge/go-1.25+-blue)](https://go.dev/)
[![License](https://img.shields.io/github/license/nduyhai/gocraft-modules)](LICENSE)
[![Multi-Module CI](https://github.com/nduyhai/gocraft-modules/actions/workflows/multi-module-ci.yml/badge.svg)](https://github.com/nduyhai/gocraft-modules/actions/workflows/multi-module-ci.yml)

A Go multi-module workspace with examples for HTTP (chi, gin), gRPC (client, server), and DB (gorm). The repo includes a multi-module aware Makefile and CI.

## Modules

- db/gorm
- grpc/client
- grpc/server
- http/chi
- http/gin

See go.work for the complete workspace list.

## Requirements

- Go 1.25+

## Quickstart

```bash
# Clone
git clone https://github.com/nduyhai/gocraft-modules
cd gocraft-modules

# Show discovered modules
make modules

# Install deps, verify, format, lint, build, and test across all modules
make all


# Run tests (all modules or a single module)
make test
make test MODULE=http/gin

# Lint all modules (or one)
make lint
make lint MODULE=grpc/server
```


## CI

- .github/workflows/multi-module-ci.yml: discovers modules and runs tidy/verify, build, test, lint per module.

## Makefile Targets (highlights)

- modules — list discovered modules
- deps, verify — manage dependencies per module
- build, test, test-coverage — with optional MODULE=path selector
- lint, fmt, goimports — code quality

Run make help for the full list.

## License

MIT — see LICENSE.

