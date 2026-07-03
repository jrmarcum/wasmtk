// wasmtk own dynamic runtime — #14 GC track, Part 2: free-list allocator (design in cmem/dynrt-design.md).
//
// Part 1 (auto-grow) only lifted the FIXED page cap — it never reclaimed memory. Part 2 makes the
// allocator able to RECLAIM: `$__free(ptr, size)` links a block (>= 8 bytes) into `$__free_list`
// (storing [blockSize@0, nextFree@4] in the block's own first 8 bytes), and `$__malloc` first-fits
// the free list before bumping. Executable-only (a merged library's malloc is dropped + replaced by
// the host's; the free-list logic would also defeat `detectBumpAllocator`). No splitting in v1.
//
// On its own the free list is dormant — nothing CALLS free yet (the GC's sweep will, in P5). This
// test exercises the allocator directly via the new `__malloc`/`__free`/`__heapPtr` intrinsics and
// self-checks (trap-on-failure) that a freed block is reused and the bump cursor doesn't advance.
// Uses @test-pipeline because the intrinsics aren't valid native TS (so run-ts is skipped).
//
// @test-pipeline
// @step wasic ../wasm_wasi_bundle/gc_bundle/freelist.ts
// @step run ../wasm_wasi_bundle/gc_bundle/freelist.wasm
