// Phase 18 — WASM Module Bundle Test
// Exercises the full 4-step pipeline: modc → wasic → wasmbundle → run
//
// Source files in tests/wasm_wasi_bundle/18_bundle/:
//   Library:     18_MathLibrary_Modc.ts      → 18_MathLibrary_Modc.wasm      (via modc)
//   Application: 18_MainApplication_Wasic.ts → 18_MainApplication_Wasic.wasm (via wasic)
//   Bundle:      both combined               → 18_WasmBundle.wasm             (via wasmbundle)
//
// Expected output (run):
//   --- Test 1: Static Function Linkage ---
//   Scaled Area Result: 60
//   --- Test 2: Shifted Data Segment Pointers ---
//   Library Version: v1.8.0-core
//
// @test-pipeline
// @step modc ../wasm_wasi_bundle/18_bundle/18_MathLibrary_Modc.ts
// @step wasic ../wasm_wasi_bundle/18_bundle/18_MainApplication_Wasic.ts
// @step wasmbundle ../wasm_wasi_bundle/18_bundle/18_MathLibrary_Modc.wasm ../wasm_wasi_bundle/18_bundle/18_MainApplication_Wasic.wasm --on-conflict=exclude -o ../wasm_wasi_bundle/18_bundle/18_WasmBundle.wasm
// @step run ../wasm_wasi_bundle/18_bundle/18_WasmBundle.wasm
