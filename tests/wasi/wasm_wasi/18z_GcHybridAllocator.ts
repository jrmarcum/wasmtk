// wasmtk own dynamic runtime — #14 GC: HYBRID allocator (segregated buckets + batch coalescing).
//
// Replaces the LIFO+splitting free list with a three-tier hybrid (cmem/dynrt-design.md):
//  • segregated buckets (16/24/28/32) — O(1) exact reuse for the dominant sizes, structurally can't
//    cycle (the hot path pays nothing);
//  • a Tier-2 general pool (first-fit + split) for other sizes;
//  • a BATCH defrag (`defragFull`) — the only coalescing site, a snapshot pass (gather → address
//    merge-sort → merge adjacent → redistribute) with no allocation re-entrancy, so it sidesteps the
//    cycle that broke coalesce-on-free. Triggered proactively (adaptive node threshold, amortized) and
//    on-demand (gated by free-bytes ≥ request, for large-request reuse).
//
// This pipeline runs the exact stress that hung coalesce-on-free (heavy allocation + collect →
// proactive defrag mid-sweep) plus mixed-size build/drop/collect cycles, and asserts the free-list
// INTEGRITY (`dynGcCheckHeap()===0`: no cycle, valid sizes, consistent counters) after every phase,
// plus bounded memory. Self-checks via trap.
//
// @test-pipeline
// @step modc ../wasm_wasi_bundle/dynrt_bundle/dynrt_lib_modc.ts
// @step wasic ../wasm_wasi_bundle/dynrt_eval_bundle/main_gchybrid.ts
// @step run ../wasm_wasi_bundle/dynrt_eval_bundle/main_gchybrid.wasm
