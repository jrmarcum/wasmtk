// wasmtk own dynamic runtime — #14 (roadmap §7-#7 / cmem/dynrt-design.md), increment 1:
// the boxed-value + dynamic-object model.
//
// DECISION: rather than depending on javyc/QuickJS for the irreducible dynamic kernel, wasmtk
// ships its OWN dynamic runtime (boxed values + property map + — later — an interpreter for
// eval/new Function). This first increment delivers ONLY the value + object substrate that the
// interpreter and the eventual wasic `any` type will lower onto. No eval, no prototype mutation.
//
// Authored in the SAME wasic TS subset as the Tier-1 caps (Set/Map/Date/JSON/RegExp), so the
// allocator, strings, dynamic arrays and number formatting all come from wasic's own codegen —
// zero duplication. Delivered as a shared-heap modc library: after the Phase 18 merge + Stage 0.6
// allocator unification, the library's $__malloc resolves to the driver's bump cursor, so boxed
// values live on the ONE heap shared with the program.
//
// A boxed value is an i32 handle = base pointer of a 4-slot Int32Array node [tag, a, b, c]:
//   tag 0=undefined 1=null 2=boolean 3=number(f64) 4=string 5=array 6=object.
// Numbers carry a Float64Array(1) payload (real JS f64); strings a Uint8Array byte buffer;
// arrays/objects reuse wasic's native dynamic i32[] (mutators write the possibly-realloc'd pointer
// back into the node).
//
// SCOPE v1: undefined/null/boolean/number/string/array/object + the dynamic operators typeof,
// === (dynStrictEq) and + (dynAdd: numeric add + string concat). Functions, eval/new Function,
// prototype mutation, and string→number coercion are later increments.
//
// Exercises: every constructor; typeof (incl. the null/array/object → "object" quirk); ToBoolean
// / ToNumber coercions; object set/get/has/overwrite/absent; array push past initial capacity
// (forces growth → node pointer write-back); strict equality across primitives + object reference
// identity; and `+` for numeric add and string concat — all over the shared heap. The driver is
// self-checking and traps (nonzero exit) on any wrong result, so this step's success proves
// semantics, not just "it ran".
//
// Pipeline:
//   1. modc  — compile the dynamic-runtime library  → dynrt_lib_modc.wasm
//   2. wasic — compile the driver (imports the .wasm); the merge splices the library and unifies
//              the allocator
//   3. run   — execute; self-checking, traps on any wrong result
//
// @test-pipeline
// @step modc ../wasm_wasi_bundle/dynrt_bundle/dynrt_lib_modc.ts
// @step wasic ../wasm_wasi_bundle/dynrt_bundle/main_wasic.ts
// @step run ../wasm_wasi_bundle/dynrt_bundle/main_wasic.wasm
