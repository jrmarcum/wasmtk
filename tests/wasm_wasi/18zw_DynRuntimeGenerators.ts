// @test-pipeline
// #14 Route A 2e.9 — dynrt generators (`function*` / `yield`). Compiles the dynrt library (modc) + a
// self-checking driver (wasic), then runs it. The driver traps on any wrong result, so a clean `run`
// proves generators in eval source. The re-parse interpreter can't suspend a call stack, so generators
// use EAGER COLLECTION: calling a `function*` runs the body to completion, collecting each `yield` into
// an array; the generator object serves them via `.next()` → `{ value, done }` and via `for...of`.
// Covers next-sequence/done, for-of, loops, params, computed + conditional yields, and NESTED generators
// (each collects into its own array, rooted across nested calls). Finite generators only (v1).
// @step modc ../wasm_wasi_bundle/dynrt_bundle/dynrt_lib_modc.ts
// @step wasic ../wasm_wasi_bundle/dynrt_eval_bundle/main_generators.ts
// @step run ../wasm_wasi_bundle/dynrt_eval_bundle/main_generators.wasm
