// Regression (wasmmerge relocateDataPtrs): an arithmetic constant that coincidentally lands inside a
// merged library's static-data range must NOT be relocated. modByInRange does `x % 271`; 271 is inside
// the library's data range [260, ~301). Old heuristic relocated all in-range constants -> corrupted the
// divisor -> wrong result -> guard trap -> FAIL. Fix excludes pure-arithmetic (rem/mul/and/shl/...)
// operands while still relocating the banner string POINTER. Self-checking via trap-on-failure.
//
// @test-pipeline
// @step modc ../wasm_wasi_bundle/relocfix_bundle/reloc_lib_modc.ts
// @step wasic ../wasm_wasi_bundle/relocfix_bundle/main_wasic.ts
// @step run ../wasm_wasi_bundle/relocfix_bundle/main_wasic.wasm
