// wasmtk own dynamic runtime via VIRTUAL import — #14, increment 1b (feature-level tree-shake,
// stdlib-bundling brief §7-#4; design in cmem/dynrt-design.md).
//
// Unlike 18j (which imports the runtime from a fixture .wasm and needs a separate `modc` step),
// this driver imports the dynamic runtime BY NAME via `wasmtk:dynrt`. The library is embedded in
// the compiler (src/wasm/caps_bytes.ts) and merged on demand — so the pipeline is just compile +
// run, and the runtime is bundled only because it is imported here (tree-shake).
//
// The driver is self-checking and traps (nonzero exit) on any wrong result, so a successful `run`
// proves the boxed-value + dynamic-object model works over the shared heap when pulled in through
// the virtual-import path: primitives + typeof, number f64 round-trip, object set/get/has/overwrite,
// array push past capacity, and the `===` / `+` operators.
//
// @test-pipeline
// @step wasic ../wasm_wasi_bundle/dynrt_vcap_bundle/main_wasic.ts
// @step run ../wasm_wasi_bundle/dynrt_vcap_bundle/main_wasic.wasm
