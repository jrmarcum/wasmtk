// wasmtk own dynamic runtime — #14, increment 2b: variables + environment + member/index access
// (design + log in cmem/dynrt-design.md).
//
// Extends the increment-2a expression evaluator with an ENVIRONMENT: `dynEvalEnv(src, env)` resolves
// bare identifiers against `env` (a value-model object: names → boxed values) and navigates them via
// `.prop`, `["key"]`, and `[i]`. Authored in the same wasic TS subset (the subset continues to carry
// the interpreter — no rtcore/hand-WAT needed).
//
// Member access is TOTAL/guarded: `obj.prop` → undefined if absent, array/string `.length` work, and
// a member of a non-container (`undefined.x`) → undefined rather than a trap. Calls + function values
// + REAL short-circuit move to the next sub-increment: short-circuit is only observable with
// side-effecting operands (i.e. calls), and the guarded member access removes the only trap-safety
// motivation for it in 2b.
//
// Delivered as a shared-heap modc capability (the runtime library gained `dynEvalEnv` + `dynMember`/
// `dynIndexValue` + robust identifier tokenisation). The driver builds an env
// `{ x, y, name, pt:{a,b}, arr:[…] }` and self-checks variable arithmetic, object member access
// (`.prop`/`["key"]`), array index (incl. a computed index `arr[x-9]`), `.length`, string variables,
// absent→undefined, guarded `undefined.x`, and variables in ternaries — all over the shared heap.
//
// Pipeline:
//   1. modc  — compile the dynamic-runtime library (incl. the env evaluator) → dynrt_lib_modc.wasm
//   2. wasic — compile the driver (imports the .wasm); the merge splices the library + unifies the allocator
//   3. run   — execute; self-checking, traps on any wrong result
//
// @test-pipeline
// @step modc ../wasm_wasi_bundle/dynrt_bundle/dynrt_lib_modc.ts
// @step wasic ../wasm_wasi_bundle/dynrt_eval_bundle/main_env.ts
// @step run ../wasm_wasi_bundle/dynrt_eval_bundle/main_env.wasm
