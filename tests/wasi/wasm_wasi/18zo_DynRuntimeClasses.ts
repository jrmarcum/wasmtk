// @test-pipeline
// #14 Route A 2e.8 — dynrt CLASSES (built on 2f.1 this+prototype). Compiles the dynrt library (modc) +
// a self-checking driver (wasic), then runs it. The driver traps on any wrong result, so a clean `run`
// proves: `class Name { constructor(p){…} method(p){…} }` builds a class value; `new Name(args)` makes
// an instance whose __proto__ is the prototype, runs the constructor with `this`=instance (so
// `this.field = …` populates it), and method calls dispatch through the prototype binding `this`;
// instances are independent; methods call sibling methods via `this.other()`.
//
// ALSO the regression test for a general wasic fix surfaced here: `parseClasses` scanned RAW source
// (string-blind), so a `class … {}` inside this driver's eval-source STRINGS was mis-parsed as a real
// wasic class. parseClasses now detects over a code-only mask (maskCode) — see compiler-bugs.md.
// @step modc ../wasm_wasi_bundle/dynrt_bundle/dynrt_lib_modc.ts
// @step wasic ../wasm_wasi_bundle/dynrt_eval_bundle/main_classes.ts
// @step run ../wasm_wasi_bundle/dynrt_eval_bundle/main_classes.wasm
