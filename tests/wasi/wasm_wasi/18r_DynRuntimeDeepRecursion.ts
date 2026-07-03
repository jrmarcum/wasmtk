// wasmtk own dynamic runtime — #14 GC track, Part 1: auto-grow heap (design in cmem/dynrt-design.md).
//
// The bump allocator never frees, so before this part the FIXED initial page count (~2 pages) capped
// deep recursion / long dynamic loops — `fib(10)` (≈177 interpreter calls) overflowed. GC Part 1
// makes `$__malloc` AUTO-GROW linear memory (`memory.grow` by ceil(deficit/64KiB) pages) when the
// bump pointer runs past the allocated pages, lifting the fixed limit to WASM's multi-GiB memory
// limit. (Emitted only in executable/WASI modules; a merged library's malloc is dropped + replaced by
// the host's, which auto-grows — see dynrt-design.md.)
//
// This driver runs `fib(15)` (610) through the dynrt INTERPRETER — ~1973 recursive calls, each
// allocating a fresh scope + reconstructing the body string — which would have overflowed the fixed
// heap before. The driver self-checks via a trap, so a successful `run` proves the auto-grow.
//
// @test-pipeline
// @step modc ../wasm_wasi_bundle/dynrt_bundle/dynrt_lib_modc.ts
// @step wasic ../wasm_wasi_bundle/dynrt_eval_bundle/main_gc.ts
// @step run ../wasm_wasi_bundle/dynrt_eval_bundle/main_gc.wasm
