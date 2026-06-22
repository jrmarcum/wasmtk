// wasmtk own dynamic runtime — #14 GC track, Part 3: cell registry (design in cmem/dynrt-design.md).
//
// For a mark-sweep to reclaim memory it must first ENUMERATE every allocation. Part 3 routes every
// boxed value-cell allocation through `mkCell`/`mkCell5`, which record the cell in a registry list
// (`__gc_reg`) — so P4 (mark) / P5 (sweep) can walk all cells and free the unmarked ones. Only value
// cells are registered; their payloads (Float64Array / Uint8Array / container lists) are reached
// THROUGH a cell and freed by reading its fields. `dynGcCellCount()` exposes the live registry size.
//
// This pipeline (modc → wasic → run) self-checks that the count rises by one per constructor call and
// scales to 20000 cells without corruption — which is what surfaced the merge mutable-global
// preservation fix (the 0-sentinel registry pointer was being clobbered to 131072 by wasmmerge's
// blanket "mutable global → page-2" rewrite, so the registry's lazy-init never fired). See
// cmem/compiler-bugs.md.
//
// @test-pipeline
// @step modc ../wasm_wasi_bundle/dynrt_bundle/dynrt_lib_modc.ts
// @step wasic ../wasm_wasi_bundle/dynrt_eval_bundle/main_gcregistry.ts
// @step run ../wasm_wasi_bundle/dynrt_eval_bundle/main_gcregistry.wasm
