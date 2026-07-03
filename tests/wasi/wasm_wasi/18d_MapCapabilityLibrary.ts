// Tier-1 stdlib capability — Map<i32, i32> as a shared-heap modc library
// (wasmtk-stdlib-bundling-brief §5 / §7 work-item #3, second deliverable).
//
// Reuses the Set<i32> hash core (linear probing + ×2 grow/rehash) and adds a parallel
// values array, so each occupied bucket holds (key, value). Like the Set capability, the
// Map is built inside a separately-compiled modc library that shares ONE live heap with
// the wasic program importing it — the library's internal $__malloc calls resolve to the
// main module's bump cursor after the Phase 18 merge + Stage 0.6 unification.
//
// Pipeline:
//   1. modc  — compile the Map capability library  → map_lib_modc.wasm
//   2. wasic — compile the driver (imports the .wasm); the merge splices the library and
//              unifies the allocator
//   3. run   — execute; the driver is self-checking and traps (nonzero exit) on any wrong
//              result, so this step's success proves Map semantics, not just "it ran"
//
// Exercises: insert, value retrieval, update-existing-key (count stable, value changes),
// membership (present/absent), get-with-fallback on absent keys, multiple grow+rehash
// cycles, correct key→value survival across rehash, and negative keys — over the shared heap.
//
// @test-pipeline
// @step modc ../wasm_wasi_bundle/map_bundle/map_lib_modc.ts
// @step wasic ../wasm_wasi_bundle/map_bundle/main_wasic.ts
// @step run ../wasm_wasi_bundle/map_bundle/main_wasic.wasm
