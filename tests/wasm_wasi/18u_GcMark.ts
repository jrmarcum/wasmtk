// wasmtk own dynamic runtime — #14 GC track, Part 4a: mark phase (design in cmem/dynrt-design.md).
//
// Part 3 made every cell enumerable (the registry). Part 4a adds the MARK half of mark-sweep: from a
// root handle, recursively mark every reachable cell. The mark bit is bit 8 of a cell's slot-0 tag
// (uniform across cell sizes, no extra storage); the real tag is bits 0..7, so mark/sweep read
// `slot0 & 255`. The bit doubles as the visited set (cycles terminate), and a full collect() clears
// it on survivors before returning — so the rest of the runtime never observes a polluted tag.
//
// Roots here are passed EXPLICITLY (dynGcMark(root)); Part 4b wires the interpreter's shadow-stack as
// the real root source. This pipeline self-checks (trap-on-failure) that mark reaches exactly the live
// set across nesting, and leaves orphans unmarked.
//
// @test-pipeline
// @step modc ../wasm_wasi_bundle/dynrt_bundle/dynrt_lib_modc.ts
// @step wasic ../wasm_wasi_bundle/dynrt_eval_bundle/main_gcmark.ts
// @step run ../wasm_wasi_bundle/dynrt_eval_bundle/main_gcmark.wasm
