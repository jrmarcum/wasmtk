// wasmtk own dynamic runtime — #14 GC track, Part 5b: bounded memory (cmem/dynrt-design.md).
//
// Completes the mark-sweep GC: P5b reclaims PAYLOADS too (the constructors' Float64Array / Uint8Array
// / list allocations now flow through dynrt's recycling `dynAlloc`, and the sweep frees each garbage
// cell's payloads), and adds an AUTO-COLLECT trigger at interpreter statement boundaries (adaptive
// threshold). Statement boundaries are safe collection points — every live value is in a rooted scope
// — EXCEPT for mid-expression temporaries, so the recursive-descent evaluator now ROOTS the
// accumulated operand across each right-operand parse and the callee + args across a call (otherwise
// `fib(n-1) + fib(n-2)` would let the nested call collect the pending `fib(n-1)`).
//
// This driver runs a 10000-iteration loop that allocates ~30000 cells; WITHOUT collection the registry
// would grow unbounded, but auto-collect reclaims the per-iteration garbage so it runs in BOUNDED
// memory. Self-checks (trap): the sum is correct (no live value wrongly collected) and a final
// explicit collect leaves only the tiny live set.
//
// @test-pipeline
// @step modc ../wasm_wasi_bundle/dynrt_bundle/dynrt_lib_modc.ts
// @step wasic ../wasm_wasi_bundle/dynrt_eval_bundle/main_gcbounded.ts
// @step run ../wasm_wasi_bundle/dynrt_eval_bundle/main_gcbounded.wasm
