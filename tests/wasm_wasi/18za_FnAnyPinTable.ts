// wasmtk own dynamic runtime — #14 final item: functions-as-`any`, the host PIN TABLE.
//
// Unlike numbers/strings/objects (bindgen deep-copies them into JS values), a function is code and
// must stay a dynrt HANDLE. But the GC can't root host-held handles, so a function returned to the
// host would be collected on the next call → use-after-free. The pin table fixes that: `dynGcPin(h)`
// records a handle in a slot list that `dynGcMarkRoots` also marks, so it survives collections until
// `dynGcUnpin(slot)`. dynrt's GC is non-moving, so the handle's address stays valid — pinning only
// needs to keep it marked. (This is the core-side enabler; bindgen's `_unbox` returns a JS proxy that
// pins, calls via `dynApply`, and releases — see src/bindgen.ts + bindgen_tests.ts.)
//
// This pipeline creates a function via the interpreter, pins it, makes it GC-unreachable except via
// the pin, collects under garbage, then calls it — a correct result (21*2=42) proves the pin kept it
// alive (else its memory would be reused). Integrity-checked; self-checks via trap.
//
// @test-pipeline
// @step modc ../wasm_wasi_bundle/dynrt_bundle/dynrt_lib_modc.ts
// @step wasic ../wasm_wasi_bundle/dynrt_eval_bundle/main_gcpin.ts
// @step run ../wasm_wasi_bundle/dynrt_eval_bundle/main_gcpin.wasm
