// @test-pipeline
// #14 Route A 2h — the full-dynamic-compile entry `wasmtk dync` (the `javyc` replacement). Compiles an
// ENTIRE dynamic TS/JS program to a self-contained WASI module by routing its whole source through
// wasmtk's OWN runtime (the embedded `wasmtk:dynrt` interpreter) — no external Javy/QuickJS. The program
// exercises closures, a class with a method, Array methods (slice/sort/map/reduce/join), a for-loop, and
// `console.log` (which now prints from inside the interpreter via the `__host_print` import). A clean
// `run` proves the dync pipeline end-to-end. Byte-exact OUTPUT parity against a `deno run` JS baseline is
// the separate gate `tests/dync_conformance_tests.ts` (demo1/demo2/demo3, 3/3).
// @step dync ../wasm_wasi_dync/demo1.ts
// @step run ../wasm_wasi_dync/demo1.wasm
