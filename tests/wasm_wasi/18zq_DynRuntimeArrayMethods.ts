// @test-pipeline
// #14 Route A 2f.2 — dynrt built-in ARRAY METHODS (first stdlib increment). Compiles the dynrt library
// (modc) + a self-checking driver (wasic), then runs it. The driver traps on any wrong result, so a
// clean `run` proves the array-method surface in eval source: push / indexOf / includes / join / slice /
// concat / reverse, plus the callback methods map / filter / forEach / reduce (callback called with
// element + index), and method chaining (filter().map()). Dispatched in parsePostfix when the receiver
// is a tag-5 array and the member isn't a user function (so `arr[i]()` + user-set arr.foo() still win).
// @step modc ../wasm_wasi_bundle/dynrt_bundle/dynrt_lib_modc.ts
// @step wasic ../wasm_wasi_bundle/dynrt_eval_bundle/main_arraymethods.ts
// @step run ../wasm_wasi_bundle/dynrt_eval_bundle/main_arraymethods.wasm
