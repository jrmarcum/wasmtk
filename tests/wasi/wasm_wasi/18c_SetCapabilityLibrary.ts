// Tier-1 stdlib capability — Set<i32> as a shared-heap modc library
// (wasmtk-stdlib-bundling-brief §5 / §7 work-item #3, first deliverable).
//
// This is the headline use case the Stage 0.6 allocator-unification pass was built for:
// a hash table built inside a separately-compiled modc library shares ONE live heap with
// the wasic program that imports it. The library's internal $__malloc calls resolve to the
// main module's bump cursor after the Phase 18 merge + unification.
//
// Pipeline:
//   1. modc  — compile the Set capability library  → set_lib_modc.wasm
//   2. wasic — compile the driver (imports the .wasm); the merge splices the library and
//              unifies the allocator
//   3. run   — execute; the driver is self-checking and traps (nonzero exit) on any wrong
//              result, so this step's success proves Set semantics, not just "it ran"
//
// Exercises: insert, dedup, membership (present/absent), multiple grow+rehash cycles,
// survival of keys across rehash, and negative keys — all over the shared heap.
//
// @test-pipeline
// @step modc ../wasm_wasi_bundle/set_bundle/set_lib_modc.ts
// @step wasic ../wasm_wasi_bundle/set_bundle/main_wasic.ts
// @step run ../wasm_wasi_bundle/set_bundle/main_wasic.wasm
