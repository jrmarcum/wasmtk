// Alloc-free, MERGEABLE Go leaf library (built via `modc --lang=go --go-target=wasm-unknown`).
// Pure-compute exported functions — no Go runtime allocation — so the `wasm-unknown` output has
// 0 imports and no memory.grow and can be wasmmerge'd into a wasic build.
package main

//go:wasmexport addi
func addi(a int32, b int32) int32 { return a + b }

//go:wasmexport muli
func muli(a int32, b int32) int32 { return a * b }

//go:wasmexport clampi
func clampi(v int32, lo int32, hi int32) int32 {
	if v < lo {
		return lo
	}
	if v > hi {
		return hi
	}
	return v
}

func main() {}
