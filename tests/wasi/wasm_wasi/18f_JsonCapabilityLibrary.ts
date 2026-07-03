// Tier-1 stdlib capability — JSON (parse + navigate) as a shared-heap modc library
// (wasmtk-stdlib-bundling-brief §5 / §7 work-item #3, fourth deliverable).
//
// The headline JSON case: a wasic program — which has no native JSON — gains JSON.parse plus
// a navigation API by merging a separately-compiled modc library. After the Phase 18 merge +
// Stage 0.6 allocator unification, the library's internal $__malloc calls resolve to the main
// module's bump cursor, so the parsed value tree lives on the ONE heap shared with the driver.
//
// Unlike Set/Map (i32-only across the boundary) and Date (a pure-integer leaf), JSON is the
// first capability to take STRING input across the merge — the JSON document is passed as a
// wasic string (ptr+len), and object keys / string comparisons are passed in the same way.
// Several compiler gaps surfaced and were fixed to make this work (see CLAUDE.md § "Stage 0.7
// — JSON capability"): string args to merged imports (recovered from the sibling .wit), an
// allocator-detector false-positive on `global += param; return global`, escaped-quote string
// literals (`\"` inside a literal), and a findBinaryOp tail-depth bug that hid an operator
// whose RHS ended in a call (e.g. `v[i] !== t.charCodeAt(i)`).
//
// The value tree: each handle is the base pointer of a 4-slot Int32Array node
// [tag, a, b, c]; containers reuse wasic's native dynamic i32[]; string values are decoded
// into Uint8Array buffers. SCOPE v1: null / bool / integer numbers / strings / arrays /
// objects; basic string escapes (\" \\ \/ \b \f \n \r \t). Float numbers and \u are the
// documented v2 gap (mirroring Set<i32> / Map<i32,i32> scoping to integer keys first).
//
// Pipeline:
//   1. modc  — compile the JSON capability library  → json_lib_modc.wasm
//   2. wasic — compile the driver (imports the .wasm); the merge splices the library and
//              unifies the allocator
//   3. run   — execute; the driver is self-checking and traps (nonzero exit) on any wrong
//              result, so this step's success proves JSON semantics, not just "it ran"
//
// Exercises: object/array/string/number(incl. negative)/bool/null parsing, nested objects and
// arrays, object key lookup (present + absent), membership, byte-accurate string equality and
// char access, and escape decoding — all over the shared heap.
//
// @test-pipeline
// @step modc ../wasm_wasi_bundle/json_bundle/json_lib_modc.ts
// @step wasic ../wasm_wasi_bundle/json_bundle/main_wasic.ts
// @step run ../wasm_wasi_bundle/json_bundle/main_wasic.wasm
