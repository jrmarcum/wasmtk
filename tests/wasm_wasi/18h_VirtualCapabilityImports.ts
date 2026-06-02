// Tier-1 stdlib capabilities via VIRTUAL imports — feature-level tree-shake
// (stdlib-bundling brief §7 work-item #4).
//
// Unlike 18c–18g (which import each capability from a fixture .wasm and need a separate
// `modc` step), this driver imports every capability by NAME — `wasmtk:set`, `wasmtk:map`,
// `wasmtk:date`, `wasmtk:json`, `wasmtk:regex`. The capability libraries are embedded in the
// compiler (src/wasm/caps_bytes.ts) and merged on demand: only the ones imported get bundled.
//
// So the pipeline is just compile + run — no modc step. The driver is self-checking and traps
// (nonzero exit) on any wrong result, so a successful `run` proves all five capabilities work
// over the shared heap when pulled in through the virtual-import path.
//
// @test-pipeline
// @step wasic ../wasm_wasi_bundle/vcap_bundle/main_wasic.ts
// @step run ../wasm_wasi_bundle/vcap_bundle/main_wasic.wasm
