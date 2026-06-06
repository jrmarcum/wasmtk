// Go producer fixture for `wasmtk wasic --lang=go` (polyglot-producer track).
//
// NOT run by the standard test suite (tests/wasi_tests.ts) — building it needs the TinyGo (or Go)
// toolchain, which is not assumed present on every machine/CI. Manual verification:
//
//   wasmtk wasic --lang=go tests/go_fixtures/hello.go      # TinyGo (auto-fallback to binaryen-ts -Oz)
//   wasmtk run tests/go_fixtures/hello.wasm                # -> "hello from go" then "42"
//   wasmtk wasic --lang=go --go-runtime=std tests/go_fixtures/hello.go   # stdlib go fallback
//
// Numerics-first scope: command mode (func main -> _start). Go string/aggregate HOST bindings
// (bindgen) are deferred (see roadmap: ABI forward-alignment + Go bindgen).

package main

import "fmt"

func add(a, b int32) int32 { return a + b }

func main() {
	fmt.Println("hello from go")
	fmt.Println(add(20, 22))
}
