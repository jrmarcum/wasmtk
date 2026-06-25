// wasmtk own dynamic runtime — #14 Route A increment 2e.5: operators in eval source (fifth
// javyc-retirement language increment; design + log in cmem/dynrt-design.md).
//
// Adds to the dynrt interpreter: `typeof` (parseUnary → type string), nullish coalescing `??`
// (parseOr — 0/false are NOT nullish), optional chaining `?.` (parsePostfix — member/index, with
// short-circuit propagation), and array spread `[...a, ...b]` (parsePrimary). Pipeline: compile the
// dynrt library (modc), then the self-checking driver (wasic), then run it.
//
// @test-pipeline
// @step modc ../wasm_wasi_bundle/dynrt_bundle/dynrt_lib_modc.ts
// @step wasic ../wasm_wasi_bundle/dynrt_eval_bundle/main_operators.ts
// @step run ../wasm_wasi_bundle/dynrt_eval_bundle/main_operators.wasm
