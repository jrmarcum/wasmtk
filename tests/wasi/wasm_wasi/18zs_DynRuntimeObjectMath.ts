// @test-pipeline
// #14 Route A 2f.4 — dynrt Object + Math statics (stdlib increment). Compiles the dynrt library (modc) +
// a self-checking driver (wasic), then runs it. The driver traps on any wrong result, so a clean `run`
// proves the namespace-static surface in eval source: Math.floor/ceil/round/trunc/abs/sqrt/sign/min/max/
// pow + Math.PI/Math.E (reusing the wasic compiler's f64 intrinsics), and Object.keys/values/entries/
// assign (Object.create shipped in 2f.1). Both are special-cased in parsePrimary as `NS.method(args)`.
// @step modc ../wasm_wasi_bundle/dynrt_bundle/dynrt_lib_modc.ts
// @step wasic ../wasm_wasi_bundle/dynrt_eval_bundle/main_objectmath.ts
// @step run ../wasm_wasi_bundle/dynrt_eval_bundle/main_objectmath.wasm
