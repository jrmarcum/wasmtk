// wasmtk own dynamic runtime — #14 Route A increment 2e.2: literals in eval source (the second
// javyc-retirement language increment; design + log in cmem/dynrt-design.md).
//
// Adds to the dynrt interpreter (parsePrimary): array literals `[…]`, object literals `{…}` (with
// "quoted" / shorthand keys), and template literals `` `…${expr}…` ``. Also unlocks `for…of` over an
// inline array literal. Pipeline: compile the dynrt library (modc), then the self-checking driver
// (wasic), then run it — the driver traps on any wrong result, so a clean run proves the literal forms.
//
// @test-pipeline
// @step modc ../wasm_wasi_bundle/dynrt_bundle/dynrt_lib_modc.ts
// @step wasic ../wasm_wasi_bundle/dynrt_eval_bundle/main_literals.ts
// @step run ../wasm_wasi_bundle/dynrt_eval_bundle/main_literals.wasm
