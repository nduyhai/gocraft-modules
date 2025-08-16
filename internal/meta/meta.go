package meta

// Package meta provides minimal metadata to ensure the root module
// contains at least one Go package, allowing `go mod tidy` to operate
// without warnings in a multi-module repository.

// Version indicates the library version for the root module. It is
// not used by the submodules; it exists to keep the root module
// non-empty for Go tooling.
const Version = "0.0.0"
