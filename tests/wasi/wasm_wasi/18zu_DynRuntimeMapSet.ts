// @test-pipeline
// #14 Route A 2f.6 — dynrt Map + Set (stdlib bridge). Compiles the dynrt library (modc) + a self-checking
// driver (wasic), then runs it. The driver traps on any wrong result, so a clean `run` proves Map + Set
// in eval source: `new Map()` / `new Set(iterable)` build a dynrt object carrying internal key/value
// arrays. Map = set/get/has/delete/keys/values/forEach/size (chainable set, update-in-place). Set =
// add/has/delete/values/forEach/size (chainable add; constructor de-dups an array). Keys/values are
// arbitrary boxed values compared with === ; methods dispatch in parsePostfix, `.size` via dynMember.
// @step modc ../wasm_wasi_bundle/dynrt_bundle/dynrt_lib_modc.ts
// @step wasic ../wasm_wasi_bundle/dynrt_eval_bundle/main_mapset.ts
// @step run ../wasm_wasi_bundle/dynrt_eval_bundle/main_mapset.wasm
