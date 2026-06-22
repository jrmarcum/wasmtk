// wasmtk own dynamic runtime — #14, increment 2d.2: user-defined functions + `new Function`
// (design + log in cmem/dynrt-design.md). This completes the interpreter track (#14 increment 2).
//
// Adds USER function values (tag 7, marker id -1; a 5-slot cell holding the body source, the param
// names, and the DEFINING env). Two ways to create them: in-source `function name(params){body}`
// declarations (the body's source text is captured by a brace-depth scan), and `dynMakeFunc(
// paramsArr, bodyStr, env)` — the `new Function` capability: build a callable from STRINGS at
// runtime. A call sets up a fresh scope whose PARENT is the function's defining env, binds the args
// to the params, and runs the body via `dynRun`; identifier resolution walks that scope chain
// (`envLookup`), which is what makes RECURSION and closures-over-outer-vars work. The hard part is
// parser reentrancy: a user call re-enters `dynRun` (which resets the shared cursor/env/return
// globals), so `dynApply` saves/restores them around the nested run (the source string is a
// parameter, so each source stays on its own call stack).
//
// Authored in the same wasic TS subset — still no `rtcore`/hand-WAT needed.
//
// The driver self-checks (via traps): in-source decls + calls, RECURSION (factorial, fibonacci),
// closure over an outer `let`, mutually-calling functions, a function with its own locals + loop,
// functions calling built-ins, and `new Function` built from strings then called through eval.
//
// KNOWN LIMITATION (exercised at modest depth on purpose): each call allocates a fresh scope and
// reconstructs the body string, and the bump allocator never frees — so deep recursion / very many
// calls exhaust the merged module's heap (e.g. fib(10) ≈ 177 calls overflows ~2 pages; fib(8) is
// used here). This is the no-GC bump-allocator reality, documented in cmem/dynrt-design.md.
//
// Pipeline:
//   1. modc  — compile the dynamic-runtime library (incl. user functions) → dynrt_lib_modc.wasm
//   2. wasic — compile the driver (imports the .wasm); the merge splices the library + unifies the allocator
//   3. run   — execute; self-checking, traps on any wrong result
//
// @test-pipeline
// @step modc ../wasm_wasi_bundle/dynrt_bundle/dynrt_lib_modc.ts
// @step wasic ../wasm_wasi_bundle/dynrt_eval_bundle/main_func.ts
// @step run ../wasm_wasi_bundle/dynrt_eval_bundle/main_func.wasm
