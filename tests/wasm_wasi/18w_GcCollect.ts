// wasmtk own dynamic runtime — #14 GC track, Part 5a: mark-sweep collect (cmem/dynrt-design.md).
//
// The capstone: `dynGcCollect()` ties the track together — mark from all roots (P4a/P4b), then sweep
// the registry (P3): every UNMARKED value cell is garbage → return it to dynrt's own recycling free
// list (P5's `dynFreeBlock`) and drop it from the registry (compacted in place); marked cells survive
// with their mark cleared. dynrt now allocates cells through `dynAlloc`, which REUSES reclaimed blocks
// before bumping — so the collector reclaims into the same pool it allocates from (no dependency on
// wasmmerge unifying the wasic `$__free`). `dynGcMarkRoots` also marks the interpreter "registers"
// (evalEnv / last / return value), so a collection is safe to run at any point.
//
// v5a reclaims the CELLS (24/28 bytes); payloads (Float64Array / Uint8Array / lists) are reclaimed in
// P5b. Self-checks (trap-on-failure): collect reclaims the garbage, compacts the registry, a live
// value held in a rooted env survives intact, and reclaimed blocks are reused by later allocations.
//
// @test-pipeline
// @step modc ../wasm_wasi_bundle/dynrt_bundle/dynrt_lib_modc.ts
// @step wasic ../wasm_wasi_bundle/dynrt_eval_bundle/main_gccollect.ts
// @step run ../wasm_wasi_bundle/dynrt_eval_bundle/main_gccollect.wasm
