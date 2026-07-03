// wasmtk own dynamic runtime — #14, increment 2d.1: statements + control flow
// (design + log in cmem/dynrt-design.md).
//
// Layers a STATEMENT interpreter (`dynRun(src, env)`) on the 2a–2c expression evaluator: `let`/
// `const`/`var` declarations + bare-identifier assignment (both mutate the env object via `dynSet`),
// `if`/`else`, `while`, `{ blocks }`, expression statements, and `return`. Authored in the same wasic
// TS subset — the statement layer is recursive-descent + a mutable env + the direct-eval re-parse
// trick for loops (`while` re-sets the cursor to the condition start each iteration; dead branches of
// `if`/`while` reuse the 2c `evalLive` skip-parse machinery to advance the cursor without executing).
// So no rtcore extraction / hand-WAT was needed (the subset still suffices).
//
// SCOPE 2d.1: no block scoping (all declarations land in the one flat env), no `for`, no
// member-assignment (`obj.x =`), no user functions — `new Function` is 2d.2 (it adds parser-
// reentrancy save/restore on top of this statement executor).
//
// The driver runs real little programs and self-checks via traps: declarations + assignment,
// if/else (incl. no-else and early `return`), while loops (sum, factorial, fibonacci), nested loops,
// conditional accumulation, `return` out of a loop, and built-in calls inside statements — all over
// the shared heap. A successful `run` proves the statement interpreter.
//
// Pipeline:
//   1. modc  — compile the dynamic-runtime library (incl. dynRun) → dynrt_lib_modc.wasm
//   2. wasic — compile the driver (imports the .wasm); the merge splices the library + unifies the allocator
//   3. run   — execute; self-checking, traps on any wrong result
//
// @test-pipeline
// @step modc ../wasm_wasi_bundle/dynrt_bundle/dynrt_lib_modc.ts
// @step wasic ../wasm_wasi_bundle/dynrt_eval_bundle/main_run.ts
// @step run ../wasm_wasi_bundle/dynrt_eval_bundle/main_run.wasm
