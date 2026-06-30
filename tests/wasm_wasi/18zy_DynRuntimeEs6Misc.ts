// @test-pipeline
// #14 Route A 2e.11 — the remaining ES6 surface in dynrt eval source: `instanceof`, object spread
// `{ ...o }`, call spread `f(...args)`, array/object destructuring (`const [a, b] = …`,
// `const { x, y } = …` incl. holes and `key: alias` rename), and class expressions
// (`const C = class {…}`, anonymous + `extends`). Compiles the dynrt library (modc) + a self-checking
// driver (wasic), then runs it. A clean `run` proves the whole 2e.11 surface (the driver traps on the
// first wrong result, so a nonzero exit would fail this pipeline).
// @step modc ../wasm_wasi_bundle/dynrt_bundle/dynrt_lib_modc.ts
// @step wasic ../wasm_wasi_bundle/dynrt_eval_bundle/main_es6misc.ts
// @step run ../wasm_wasi_bundle/dynrt_eval_bundle/main_es6misc.wasm
