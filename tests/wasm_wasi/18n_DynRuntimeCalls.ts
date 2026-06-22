// wasmtk own dynamic runtime — #14, increment 2c: function values + calls + REAL short-circuit
// (design + log in cmem/dynrt-design.md).
//
// Adds CALLABLE function values to the evaluator. A function value is a boxed cell with tag 7 and a
// built-in id; dispatch is a STATIC switch on that id — wasmmerge forbids `call_indirect` in a merged
// module, so the runtime can't use an indirect-call table, and built-ins keyed by id are the
// merge-safe way to expose callable values (user-defined functions / `new Function` are 2d). The
// runtime ships `dynStdEnv()` pre-populated with abs/sqrt/floor/ceil/round/min/max/len + the one
// side-effecting built-in `inc` (increments a counter), so SHORT-CIRCUIT is observable.
//
// REAL short-circuit lands here (it was deferred from 2b because it is only observable/testable with
// side-effecting operands): the direct-eval parser threads a module-level `evalLive` flag, saved/
// restored at each `&&`/`||`/`?:`, and the CALL dispatch (the only side-effecting op) is skipped in a
// dead branch while the cursor still advances. The driver proves it via the inc() counter:
// `false && inc()` leaves the counter at 0, `true && inc()` at 1, `false||inc()`/`true?inc():inc()`
// etc. — including short-circuit INSIDE call args (`max(false && inc(), true && inc())` → 1 call).
//
// Also exercises the call surface itself: abs/sqrt/floor/ceil/round/min/max/len, calls over
// variables, nested calls as args (`max(abs(-5), 2)`), composition, and function-value typeof. All
// over the shared heap; the driver self-checks via traps, so a successful `run` proves the semantics.
//
// Pipeline:
//   1. modc  — compile the dynamic-runtime library (incl. calls + short-circuit) → dynrt_lib_modc.wasm
//   2. wasic — compile the driver (imports the .wasm); the merge splices the library + unifies the allocator
//   3. run   — execute; self-checking, traps on any wrong result
//
// @test-pipeline
// @step modc ../wasm_wasi_bundle/dynrt_bundle/dynrt_lib_modc.ts
// @step wasic ../wasm_wasi_bundle/dynrt_eval_bundle/main_calls.ts
// @step run ../wasm_wasi_bundle/dynrt_eval_bundle/main_calls.wasm
