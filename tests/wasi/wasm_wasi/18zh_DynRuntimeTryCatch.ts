// @test-pipeline
// #14 Route A 2e.6 — dynrt `throw` / `try` / `catch` / `finally` in eval source. Compiles the dynrt
// library (modc) + a self-checking driver (wasic), then runs it. The driver traps on any wrong result,
// so a clean `run` proves exception handling: throw propagation through statements/loops/calls, catch
// binding (and binding-less `catch {}`), finally-always-runs, and nested try/catch re-throw.
// @step modc ../wasm_wasi_bundle/dynrt_bundle/dynrt_lib_modc.ts
// @step wasic ../wasm_wasi_bundle/dynrt_eval_bundle/main_trycatch.ts
// @step run ../wasm_wasi_bundle/dynrt_eval_bundle/main_trycatch.wasm
