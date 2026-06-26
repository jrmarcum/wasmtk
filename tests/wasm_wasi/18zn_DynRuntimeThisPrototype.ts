// @test-pipeline
// #14 Route A 2f.1 — dynrt `this` + prototype (the object-model foundation for 2e.8 classes). Compiles
// the dynrt library (modc) + a self-checking driver (wasic), then runs it. The driver traps on any wrong
// result, so a clean `run` proves: object-literal method shorthand `{ m() {…} }` (and `m: function(){…}`)
// creates a function property; `obj.m(args)` binds `this` to the receiver (read + write `this.field`);
// methods call sibling methods via `this.other()`; a plain call has `this === undefined`; and
// `Object.create(proto)` builds an object whose member lookup walks the prototype chain (own shadows).
// @step modc ../wasm_wasi_bundle/dynrt_bundle/dynrt_lib_modc.ts
// @step wasic ../wasm_wasi_bundle/dynrt_eval_bundle/main_thisproto.ts
// @step run ../wasm_wasi_bundle/dynrt_eval_bundle/main_thisproto.wasm
