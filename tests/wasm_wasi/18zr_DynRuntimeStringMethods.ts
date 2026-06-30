// @test-pipeline
// #14 Route A 2f.3 — dynrt built-in STRING METHODS (stdlib increment). Compiles the dynrt library (modc)
// + a self-checking driver (wasic), then runs it. The driver traps on any wrong result, so a clean `run`
// proves the string-method surface in eval source: charAt / charCodeAt / toUpperCase / toLowerCase /
// trim / slice (incl. negative) / indexOf / includes / startsWith / endsWith / repeat / padStart /
// padEnd / concat / split, plus chaining. Dispatched in parsePostfix when the receiver is a tag-4 string
// (the dynrt string is unboxed to a wasic `string` and the compiler's own string ops do the work).
// @step modc ../wasm_wasi_bundle/dynrt_bundle/dynrt_lib_modc.ts
// @step wasic ../wasm_wasi_bundle/dynrt_eval_bundle/main_stringmethods.ts
// @step run ../wasm_wasi_bundle/dynrt_eval_bundle/main_stringmethods.wasm
