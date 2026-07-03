// @test-pipeline
// #14 Route A 2e.7a — dynrt PER-ITERATION `let` binding. Compiles the dynrt library (modc) + a
// self-checking driver (wasic), then runs it. The driver traps on any wrong result, so a clean `run`
// proves per-iteration capture: `for (let i …)` / `for (const x of …)` give each iteration a fresh
// binding (a closure made in the body captures that iteration's value, 0,1,2 — not the shared 3,3,3),
// while `var` deliberately stays a single shared binding. Covers classic-for, for-of, continue, and
// body-declared `let` interacting with the loop var.
// @step modc ../wasm_wasi_bundle/dynrt_bundle/dynrt_lib_modc.ts
// @step wasic ../wasm_wasi_bundle/dynrt_eval_bundle/main_periter.ts
// @step run ../wasm_wasi_bundle/dynrt_eval_bundle/main_periter.wasm
