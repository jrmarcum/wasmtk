// wasmtk own dynamic runtime — #14 GC track, Part 4b: interpreter shadow-stack (cmem/dynrt-design.md).
//
// P4a marked from an EXPLICIT root. P4b supplies the REAL roots: a precise collector must know every
// live handle, and wasic locals holding `any` aren't enumerable — but the INTERPRETER's live state
// is exactly its chain of active scopes. `dynRun` pushes its scope onto an explicit root stack
// (`__gc_roots`) on entry and pops on exit, so during a nested call the stack holds every frame that
// will resume. `dynGcMarkRoots()` marks from every root; `gcMark` now also follows an env's parent
// link (object slot 2) so marking one scope keeps the whole lexical chain + a closure's captured vars
// alive. A host can push its OWN top-level roots via `dynGcPushRoot` (P5's collect() will use this).
//
// Pipeline self-checks (trap-on-failure): push/pop BALANCE across nested recursion; mark-from-roots
// reaches a driver-pushed graph; and marking a returned closure traverses into its captured scope.
//
// @test-pipeline
// @step modc ../wasm_wasi_bundle/dynrt_bundle/dynrt_lib_modc.ts
// @step wasic ../wasm_wasi_bundle/dynrt_eval_bundle/main_gcroots.ts
// @step run ../wasm_wasi_bundle/dynrt_eval_bundle/main_gcroots.wasm
