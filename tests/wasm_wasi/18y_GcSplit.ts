// wasmtk own dynamic runtime — #14 GC polish: free-list splitting (cmem/dynrt-design.md).
//
// `dynAlloc` reused an oversized free block without splitting, so when (say) a 64B block served a 24B
// request and was later freed at its smaller logical size, the leftover bytes were lost — a slow
// size-mismatch leak. Now `dynAlloc` SPLITS: it carves the remainder (>= 16B) off the chosen block as
// its own free block at `cur + size`, so nothing is lost. (Number-heavy code already did exact reuse
// via first-fit and never split; this only bites mixed-size workloads.)
//
// This driver forces the split path — it builds + drops large arrays (large element-list blocks)
// interleaved with many small number cells, collecting between, so small allocations must reuse +
// split the freed large blocks. Self-checks (trap): correctness survives the split-heavy reuse and
// memory stays bounded (everything, incl. split leftovers, recycled).
//
// @test-pipeline
// @step modc ../wasm_wasi_bundle/dynrt_bundle/dynrt_lib_modc.ts
// @step wasic ../wasm_wasi_bundle/dynrt_eval_bundle/main_gcsplit.ts
// @step run ../wasm_wasi_bundle/dynrt_eval_bundle/main_gcsplit.wasm
