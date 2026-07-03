// @test-pipeline
// #14 Route A 2e.7 — dynrt lexical BLOCK SCOPING in eval source. Compiles the dynrt library (modc) +
// a self-checking driver (wasic), then runs it. The driver traps on any wrong result, so a clean `run`
// proves the scoping rules: each `{ }` block / `for` loop / `catch` runs in a fresh child scope so
// `let`/`const` don't leak, bare assignment `x = v` walks the chain to update the declaring scope (not
// a shadow), and the `catch (e)` binding is scoped to the catch.
// @step modc ../wasm_wasi_bundle/dynrt_bundle/dynrt_lib_modc.ts
// @step wasic ../wasm_wasi_bundle/dynrt_eval_bundle/main_scope.ts
// @step run ../wasm_wasi_bundle/dynrt_eval_bundle/main_scope.wasm
