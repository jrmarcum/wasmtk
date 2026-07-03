// Phase 18.5 — Shared-heap allocator unification across two modc libraries
//
// Exercises the wasmmerge allocator-unification pass added 2026-05-30:
//   - Two modc libraries are compiled, each carrying its own $__malloc and
//     $__heap_ptr in source form.
//   - Both libraries are imported by a main wasic program.
//   - At merge time, both libraries' $__malloc bodies are dropped and both
//     $__heap_ptr globals are dropped; every call/global ref is redirected
//     to the main module's allocator pair.
//   - At runtime, each library allocates a dynamic i32[] via push() — both
//     allocations go through the single shared bump cursor and end up at
//     disjoint addresses.
//
// Without the unification pass this fails: each library would advance its
// private $__heap_ptr (initialised to the page-2 boundary 131072) and the
// second library's first push would overlap with the first library's array.
//
// Expected stdout (last 3 lines):
//   ptrA != ptrB: true
//   disjoint: true
//
// @test-pipeline
// @step modc ../wasm_wasi_bundle/sharedheap_bundle/lib_a_modc.ts
// @step modc ../wasm_wasi_bundle/sharedheap_bundle/lib_b_modc.ts
// @step wasic ../wasm_wasi_bundle/sharedheap_bundle/main_wasic.ts
// @step run ../wasm_wasi_bundle/sharedheap_bundle/main_wasic.wasm
