// wasmtk own dynamic runtime — #14 Route A increment 2e.3: function expressions + arrow functions in
// eval source (third javyc-retirement language increment; design + log in cmem/dynrt-design.md).
//
// Adds to the dynrt interpreter (parsePrimary): anonymous `function (p) { … }` expressions and arrow
// functions `(p) => …` / `p => …` / `() => …` (block or expression body), all building user function
// VALUES that close over the current env — enabling higher-order functions + closures. Pipeline:
// compile the dynrt library (modc), then the self-checking driver (wasic), then run it.
//
// @test-pipeline
// @step modc ../wasm_wasi_bundle/dynrt_bundle/dynrt_lib_modc.ts
// @step wasic ../wasm_wasi_bundle/dynrt_eval_bundle/main_funcs.ts
// @step run ../wasm_wasi_bundle/dynrt_eval_bundle/main_funcs.wasm
