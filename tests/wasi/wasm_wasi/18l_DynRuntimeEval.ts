// wasmtk own dynamic runtime — #14, increment 2a: `eval` of a pure expression language
// (design + log in cmem/dynrt-design.md).
//
// The first piece of the interpreter (#14 increment 2): `dynEval(src)` parses and evaluates a pure
// JS EXPRESSION into a boxed value (the value model from increments 1a/1b). It is a recursive-
// descent, direct-eval parser authored in the SAME wasic TS subset as the rest of the runtime
// (decision 2026-06-22: continue in the subset; the subset already proved out recursive-descent in
// JSON and backtracking in RegExp) — so no `rtcore` extraction / hand-WAT was needed yet.
//
// Grammar (low→high): ternary `?:`, `||`, `&&`, equality `=== !== == !=`, relational `< > <= >=`,
// additive `+ -`, multiplicative `* / %`, unary `- ! +`, primary (number/string/bool/null/undefined
// literal or `( … )`). v1 covers literals + operators only — no variables, member access, calls, or
// statements yet (2b+). Because v1 expressions have NO side effects, `&&`/`||`/`?:` evaluate both
// sides and select (observationally identical to short-circuit; real short-circuit lands with 2b).
//
// Delivered as a shared-heap modc capability (the runtime library gained `dynEval` + the dynamic
// operators `dynSub/Mul/Div/Mod/Neg/Not/Lt/Gt/Le/Ge`); the driver self-checks via traps, so a
// successful `run` proves the evaluator over precedence, parens, unary, f64 literals, comparisons,
// logical, ternary, and string concat.
//
// Pipeline:
//   1. modc  — compile the dynamic-runtime library (now incl. the evaluator) → dynrt_lib_modc.wasm
//   2. wasic — compile the driver (imports the .wasm); the merge splices the library + unifies the allocator
//   3. run   — execute; self-checking, traps on any wrong result
//
// @test-pipeline
// @step modc ../wasm_wasi_bundle/dynrt_bundle/dynrt_lib_modc.ts
// @step wasic ../wasm_wasi_bundle/dynrt_eval_bundle/main_wasic.ts
// @step run ../wasm_wasi_bundle/dynrt_eval_bundle/main_wasic.wasm
