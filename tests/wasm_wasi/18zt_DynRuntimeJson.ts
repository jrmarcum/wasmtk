// @test-pipeline
// #14 Route A 2f.5 — dynrt JSON (stdlib bridge). Compiles the dynrt library (modc) + a self-checking
// driver (wasic), then runs it. The driver traps on any wrong result, so a clean `run` proves JSON in
// eval source: `JSON.parse(str)` (reuses the interpreter's own literal parser — JSON ⊂ the expression
// grammar — to build native dynrt objects/arrays/strings/numbers/bool/null) and `JSON.stringify(value)`
// (recursive serialization). Covers object/array/nested/scalars, stringify length checks, and the
// strongest case: parse∘stringify round-trips (object, array, nested object, object-with-array).
// @step modc ../wasm_wasi_bundle/dynrt_bundle/dynrt_lib_modc.ts
// @step wasic ../wasm_wasi_bundle/dynrt_eval_bundle/main_json.ts
// @step run ../wasm_wasi_bundle/dynrt_eval_bundle/main_json.wasm
