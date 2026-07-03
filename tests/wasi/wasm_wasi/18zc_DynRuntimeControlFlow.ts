// wasmtk own dynamic runtime — #14 Route A increment 2e.1: control flow (the first javyc-retirement
// language increment; design + log in cmem/dynrt-design.md "javyc retirement — scoped task breakdown").
//
// Adds to the dynrt interpreter: C-style `for`, `for…of`, `do…while`, `break`/`continue`, and the
// `++`/`--`/`+=`/`-=`/`*=`/`/=` update forms. Pipeline: compile the dynrt library (modc), then the
// self-checking driver (wasic), then run it — the driver traps on any wrong result, so a clean run
// proves the new control-flow forms.
//
// @test-pipeline
// @step modc ../wasm_wasi_bundle/dynrt_bundle/dynrt_lib_modc.ts
// @step wasic ../wasm_wasi_bundle/dynrt_eval_bundle/main_loops.ts
// @step run ../wasm_wasi_bundle/dynrt_eval_bundle/main_loops.wasm
