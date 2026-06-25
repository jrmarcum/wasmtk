// wasmtk own dynamic runtime — #14 Route A increment 2e.4: member / index assignment in eval source
// (fourth javyc-retirement language increment; design + log in cmem/dynrt-design.md).
//
// Adds to the dynrt interpreter (runStatement): `o.x = v`, `o[k] = v`, `arr[i] = v` (plain and
// `+=`/`-=`/`*=`/`/=` compound), nested targets (`o.p.v = …`, `m[i][j] = …`), and computed keys — so
// dynamic code can mutate objects/arrays in place. New setters `dynArrSet`/`dynIndexSet`. Pipeline:
// compile the dynrt library (modc), then the self-checking driver (wasic), then run it.
//
// @test-pipeline
// @step modc ../wasm_wasi_bundle/dynrt_bundle/dynrt_lib_modc.ts
// @step wasic ../wasm_wasi_bundle/dynrt_eval_bundle/main_memassign.ts
// @step run ../wasm_wasi_bundle/dynrt_eval_bundle/main_memassign.wasm
