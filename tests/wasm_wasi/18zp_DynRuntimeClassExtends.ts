// @test-pipeline
// #14 Route A 2e.8a — dynrt CLASS COMPLETION: extends / super / static / fields / getters+setters.
// Compiles the dynrt library (modc) + a self-checking driver (wasic), then runs it. The driver traps on
// any wrong result, so a clean `run` proves: `extends` (prototype-chained inheritance + inherited
// methods), `super(args)` (base constructor, incl. a three-level chain), `super.method()` (overridden
// base method with this=instance), `static` methods + fields on the class object, instance fields
// (`x = expr;` lowered to a constructor preamble), and getters/setters (`get x(){…}`/`set x(v){…}`
// invoked on member read/write). Builds on the 2e.8 core (class/constructor/new) + 2f.1 this+prototype.
// @step modc ../wasm_wasi_bundle/dynrt_bundle/dynrt_lib_modc.ts
// @step wasic ../wasm_wasi_bundle/dynrt_eval_bundle/main_classext.ts
// @step run ../wasm_wasi_bundle/dynrt_eval_bundle/main_classext.wasm
